import AudienceKit
import Foundation
import Observation
@preconcurrency import PassKit
@preconcurrency import StripeApplePay

/// How an Apple Pay sheet ended.
enum ClipPaymentOutcome: Sendable, Equatable {
    case completed
    case canceled
    case failed(String)
}

/// Cover and tips, Apple Pay only. `buyCover`/`startTip` open the payment on the
/// venue's or performer's own Stripe account (a Connect direct charge); Apple
/// Pay confirms the PaymentIntent through `StripeApplePay`, and the confirm
/// mutation checks it with Stripe so the pass or receipt is real. Square venues
/// pay in the full app: the Square SDK doesn't fit the clip's size budget.
@MainActor
@Observable
final class ClipCheckout {
    let api: ClipAPI
    let merchantID: String?
    private(set) var busy = false

    init(api: ClipAPI, merchantID: String?) {
        self.api = api
        self.merchantID = merchantID
    }

    enum CoverResult: Sendable {
        case paid(Admission)
        case canceled
        case failed(String)
    }

    /// One admission for tonight at `venue`, in `tier` or general admission.
    func payCover(venue: ClipVenue, tier: CoverTier?) async -> CoverResult {
        guard !busy else { return .canceled }
        busy = true
        defer { busy = false }
        do {
            let purchase = try await api.buyCover(venueID: venue.id, tier: tier?.id)
            switch purchase.nextStep {
            case .showPass:
                return .paid(purchase.admission)
            case let .stripe(clientSecret, publishableKey, accountID):
                let request = try paymentRequest(label: venue.name, total: purchase.admission.total)
                switch await ClipApplePay(clientSecret: clientSecret, publishableKey: publishableKey,
                                          accountID: accountID).present(request) {
                case .completed:
                    return .paid(try await api.confirmCover(admissionID: purchase.admission.id))
                case .canceled:
                    return .canceled
                case let .failed(message):
                    return .failed(message)
                }
            case .square:
                return .failed(ClipError.payInApp.localizedDescription)
            case .unavailable:
                return .failed(ClipError.unavailable.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    enum TipResult: Sendable {
        case paid(ClipTip)
        case canceled
        case failed(String)
    }

    func payTip(performer: ClipPerformer, amountCents: Int) async -> TipResult {
        guard !busy else { return .canceled }
        busy = true
        defer { busy = false }
        do {
            let purchase = try await api.startTip(personID: performer.id, amountCents: amountCents)
            if purchase.tip.isPaid { return .paid(purchase.tip) }
            switch purchase.provider {
            case "STRIPE":
                guard let secret = purchase.paymentIntentClientSecret, let key = purchase.publishableKey,
                      let account = purchase.stripeAccountId else { throw ClipError.unavailable }
                let request = try paymentRequest(label: "Tip for \(performer.displayName)", total: purchase.tip.total)
                switch await ClipApplePay(clientSecret: secret, publishableKey: key, accountID: account).present(request) {
                case .completed:
                    return .paid(try await api.confirmTip(tipID: purchase.tip.id))
                case .canceled:
                    return .canceled
                case let .failed(message):
                    return .failed(message)
                }
            case "SQUARE":
                return .failed(ClipError.payInApp.localizedDescription)
            default:
                throw ClipError.unavailable
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func paymentRequest(label: String, total: Money) throws -> PKPaymentRequest {
        guard let merchantID, PKPaymentAuthorizationController.canMakePayments() else {
            throw ClipError.applePayUnavailable
        }
        let request = PKPaymentRequest()
        request.merchantIdentifier = merchantID
        request.countryCode = "US"
        request.currencyCode = total.currency.uppercased()
        request.supportedNetworks = [.visa, .masterCard, .amex, .discover]
        request.merchantCapabilities = .threeDSecure
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(label: "Hot Mess · \(label)", amount: NSDecimalNumber(decimal: total.amount))
        ]
        return request
    }
}

/// One Apple Pay sheet for one Stripe PaymentIntent. Stripe calls its delegate
/// on the main thread, so the conformance is `@preconcurrency` with the class
/// on the main actor, as `SquareApplePay` does in the app.
@MainActor
final class ClipApplePay: NSObject, ApplePayContextDelegate {
    private let clientSecret: String
    private let apiClient: STPAPIClient
    private var context: STPApplePayContext?
    private var continuation: CheckedContinuation<ClipPaymentOutcome, Never>?

    init(clientSecret: String, publishableKey: String, accountID: String) {
        self.clientSecret = clientSecret
        let apiClient = STPAPIClient(publishableKey: publishableKey)
        apiClient.stripeAccount = accountID
        self.apiClient = apiClient
    }

    func present(_ request: PKPaymentRequest) async -> ClipPaymentOutcome {
        guard let context = STPApplePayContext(paymentRequest: request, delegate: self) else {
            return .failed("Couldn't open Apple Pay.")
        }
        context.apiClient = apiClient
        self.context = context
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            context.presentApplePay()
        }
    }

    func applePayContext(_ context: STPApplePayContext, didCreatePaymentMethod paymentMethod: StripeAPI.PaymentMethod,
                         paymentInformation: PKPayment) async throws -> String {
        clientSecret
    }

    func applePayContext(_ context: STPApplePayContext, didCompleteWith status: STPApplePayContext.PaymentStatus, error: (any Error)?) {
        let outcome: ClipPaymentOutcome
        switch status {
        case .success: outcome = .completed
        case .userCancellation: outcome = .canceled
        case .error: outcome = .failed(error?.localizedDescription ?? "The payment didn't go through.")
        }
        self.context = nil
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}
