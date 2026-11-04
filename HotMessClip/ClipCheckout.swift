import AudienceCore
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
    let guest: ClipGuestAPI
    let merchantID: String?
    private(set) var busy = false

    init(api: ClipAPI, guest: ClipGuestAPI, merchantID: String?) {
        self.api = api
        self.guest = guest
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

    // MARK: Guest checkout

    /// Tonight's cover before sign-in: start it on the clip endpoint, keep
    /// the claim token in the keychain, pay with Apple Pay, then confirm. A
    /// canceled or failed payment forgets the token; the pending admission
    /// stays the API's, as an abandoned member checkout does.
    func payGuestCover(venueID: UUID, venueName: String, night: String, tier: ClipOffer.Tier?) async -> CoverResult {
        guard !busy else { return .canceled }
        busy = true
        defer { busy = false }
        var token: String?
        do {
            let request = try paymentRequestReady()
            let started = try await guest.startCover(venueID: venueID, tier: tier?.id)
            token = started.claimToken
            store(GuestPurchase(kind: .cover, id: started.record.id, claimToken: started.claimToken,
                                host: guest.client.configuration.host, venueID: venueID.uuidString,
                                night: started.record.night))
            guard let secret = started.paymentIntentClientSecret, let key = started.publishableKey,
                  let account = started.stripeAccountId else {
                if started.record.status.lowercased() == "paid" { return .paid(started.record.admission) }
                throw ClipError.unavailable
            }
            price(request, label: venueName, total: started.record.admission.total)
            switch await ClipApplePay(clientSecret: secret, publishableKey: key, accountID: account).present(request) {
            case .completed:
                return .paid(try await guest.confirmCover(id: started.record.id, claimToken: started.claimToken).admission)
            case .canceled:
                forget(token)
                return .canceled
            case let .failed(message):
                forget(token)
                return .failed(message)
            }
        } catch {
            forget(token)
            return .failed(error.localizedDescription)
        }
    }

    /// Checks a guest pass again (it was still processing, or the clip is
    /// showing it again from the venue's link).
    func refreshGuestCover(_ purchase: GuestPurchase) async throws -> Admission {
        try await guest.confirmCover(id: purchase.id, claimToken: purchase.claimToken).admission
    }

    /// A tip before sign-in, the same way as ``payGuestCover``.
    func payGuestTip(personID: UUID, performerName: String, amountCents: Int, note: String?,
                     showFirstName: Bool) async -> TipResult {
        guard !busy else { return .canceled }
        busy = true
        defer { busy = false }
        var token: String?
        do {
            let request = try paymentRequestReady()
            let started = try await guest.startTip(personID: personID, amountCents: amountCents, note: note,
                                                   showFirstName: showFirstName)
            token = started.claimToken
            store(GuestPurchase(kind: .tip, id: started.record.id, claimToken: started.claimToken,
                                host: guest.client.configuration.host))
            guard let secret = started.paymentIntentClientSecret, let key = started.publishableKey,
                  let account = started.stripeAccountId else { throw ClipError.unavailable }
            price(request, label: "Tip for \(performerName)", total: started.record.tip.total)
            switch await ClipApplePay(clientSecret: secret, publishableKey: key, accountID: account).present(request) {
            case .completed:
                return .paid(try await guest.confirmTip(id: started.record.id, claimToken: started.claimToken).tip)
            case .canceled:
                forget(token)
                return .canceled
            case let .failed(message):
                forget(token)
                return .failed(message)
            }
        } catch {
            forget(token)
            return .failed(error.localizedDescription)
        }
    }

    private func store(_ purchase: GuestPurchase) {
        GuestPurchaseStore.shared.update { $0.add(purchase) }
    }

    private func forget(_ token: String?) {
        guard let token else { return }
        GuestPurchaseStore.shared.update { $0.remove(token: token) }
    }

    /// Apple Pay must be ready before the clip starts a purchase it can't pay.
    private func paymentRequestReady() throws -> PKPaymentRequest {
        try paymentRequest(label: "", total: Money(cents: 0))
    }

    private func price(_ request: PKPaymentRequest, label: String, total: Money) {
        request.currencyCode = total.currency.uppercased()
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(label: "Hot Mess · \(label)", amount: NSDecimalNumber(decimal: total.amount))
        ]
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
