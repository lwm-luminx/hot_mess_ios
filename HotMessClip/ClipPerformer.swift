import AudienceKit
import Foundation
import Observation
@preconcurrency import PassKit
@preconcurrency import SquareInAppPaymentsSDK
import UIKit

struct ClipPerformer: Decodable, Sendable {
    struct Tipping: Decodable, Sendable {
        struct Option: Decodable, Sendable, Identifiable {
            var id: String { name }
            let name: String
            let isInApp: Bool
            let url: URL?
        }
        let options: [Option]
        let presetCents: [Int]
        let minimumCents: Int
        let maximumCents: Int
        let currency: String
    }
    let id: UUID
    let name: String?
    let tipping: Tipping?
}

struct ClipTip: Decodable, Sendable {
    let id: String
    let status: String
    let amount: Money
    let fee: Money
    let total: Money
}

@MainActor @Observable
final class ClipTipCheckout {
    private(set) var busy = false
    var message: String?
    private(set) var paid = false

    func pay(personID: UUID, amount: Int, name: String, session: ClipSession) async {
        guard !busy, !session.paymentBusy else { return }
        busy = true
        session.tipBusy = true
        message = nil
        paid = false
        defer { busy = false; session.tipBusy = false }
        do {
            let result = try await session.client.graphQL(Self.start, variables: [
                "personId": .string(personID.uuidString), "amount": .int(amount)
            ], as: StartResponse.self)
            let purchase = result.startTip
            var tip = purchase.tip
            if tip.status != "PAID" {
                switch purchase.provider {
                case "STRIPE":
                    guard let secret = purchase.paymentIntentClientSecret,
                          let key = purchase.publishableKey, let account = purchase.stripeAccountId else {
                        throw ClipError.unavailable
                    }
                    switch await session.checkout.presentPaymentSheet(clientSecret: secret, publishableKey: key,
                            accountID: account, venueName: name) {
                    case .completed:
                        tip = try await session.client.graphQL(Self.confirm, variables: ["id": .string(tip.id)],
                            as: ConfirmResponse.self).confirmTip.tip
                    case .canceled: return
                    case let .failed(message): self.message = message; return
                    }
                case "SQUARE":
                    guard let applicationID = purchase.squareApplicationId,
                          let presenter = UIApplication.shared.topViewController else { throw ClipError.unavailable }
                    SQIPInAppPaymentsSDK.squareApplicationID = applicationID
                    let merchant = Bundle.main.object(forInfoDictionaryKey: "ApplePayMerchantID") as? String
                    let methods = SquarePaymentMethod.available(canUseApplePay: SQIPInAppPaymentsSDK.canUseApplePay,
                                                                merchantID: merchant)
                    let id = tip.id
                    let pay: @MainActor (String) async throws -> Void = { nonce in
                        tip = try await session.client.graphQL(Self.charge, variables: ["id": .string(id), "source": .string(nonce)],
                            as: PayResponse.self).payTip.tip
                    }
                    let outcome: SquareOutcome
                    switch await CoverCheckout.chooseSquareMethod(from: methods, price: tip.total.formatted, presenter: presenter) {
                    case .applePay:
                        guard let merchant else { return }
                        let request = PKPaymentRequest.squarePaymentRequest(merchantIdentifier: merchant,
                            countryCode: "US", currencyCode: tip.total.currency.uppercased())
                        request.paymentSummaryItems = [PKPaymentSummaryItem(label: name,
                            amount: NSDecimalNumber(decimal: tip.total.amount))]
                        outcome = await SquareApplePay(pay: pay).run(request)
                    case .card:
                        outcome = await SquareCardEntry(pay: pay, price: tip.total.formatted, tintColor: .systemBlue).run(from: presenter)
                    case nil: return
                    }
                    switch outcome {
                    case .completed: break
                    case .canceled: return
                    case let .failed(message): self.message = message; return
                    }
                default: throw ClipError.unavailable
                }
            }
            paid = tip.status == "PAID"
            message = paid ? "Thank you! Your tip was paid." : "Your payment is still processing."
        } catch { message = error.localizedDescription }
    }

    private struct Purchase: Decodable, Sendable {
        let tip: ClipTip
        let provider: String
        let paymentIntentClientSecret: String?
        let publishableKey: String?
        let stripeAccountId: String?
        let squareApplicationId: String?
    }
    private struct StartResponse: Decodable, Sendable { let startTip: Purchase }
    private struct Payload: Decodable, Sendable { let tip: ClipTip }
    private struct ConfirmResponse: Decodable, Sendable { let confirmTip: Payload }
    private struct PayResponse: Decodable, Sendable { let payTip: Payload }
    static let tipFields = "id status amount { cents currency } fee { cents currency } total { cents currency }"
    private static let start = """
    mutation ClipStartTip($personId: ID!, $amount: Int!) {
      startTip(input: {personId: $personId, amountCents: $amount}) {
        tip { \(tipFields) } provider paymentIntentClientSecret publishableKey stripeAccountId squareApplicationId
      }
    }
    """
    private static let confirm = """
    mutation ClipConfirmTip($id: ID!) { confirmTip(input: {tipId: $id}) { tip { \(tipFields) } } }
    """
    private static let charge = """
    mutation ClipPayTip($id: ID!, $source: String!) { payTip(input: {tipId: $id, sourceId: $source}) { tip { \(tipFields) } } }
    """
}
