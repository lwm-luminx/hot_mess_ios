import AudienceKit
import Foundation

/// Authenticated reads and the two payments the clip takes. Same audience
/// endpoint and ban checks as Hot Mess; every call here needs a session.
struct ClipAPI: Sendable {
    let client: AudienceKitClient

    // MARK: Records

    func details(for link: ClipLink) async throws -> ClipDetails {
        let id = link.id
        switch link.kind {
        case "people":
            let response = try await query(Documents.person, variables: ["id": .string(id)], as: PersonResponse.self)
            guard let person = response.people.person else { throw ClipError.unavailable }
            return ClipDetails(venue: nil, event: nil, performer: person)
        case "venues":
            let response = try await query(Documents.venue, variables: ["id": .string(id)], as: VenueResponse.self)
            guard let venue = response.venues.venue else { throw ClipError.unavailable }
            return ClipDetails(venue: venue, event: nil)
        default:
            let response = try await query(Documents.event, variables: ["id": .string(id)], as: EventResponse.self)
            guard let event = response.events.event else { throw ClipError.unavailable }
            return ClipDetails(venue: event.venue?.venue, event: event)
        }
    }

    // MARK: Cover

    func buyCover(venueID: UUID, tier: String?) async throws -> CoverPurchase {
        var variables: [String: GraphQLValue] = ["venueId": .string(venueID.uuidString), "quantity": .int(1)]
        if let tier { variables["tier"] = .string(tier) }
        return try await query(Documents.buyCover, variables: variables, as: PurchaseResponse.self).buyCover
    }

    func confirmCover(admissionID: String) async throws -> Admission {
        try await query(Documents.confirmCover, variables: ["admissionId": .string(admissionID)], as: ConfirmResponse.self).confirmCover.admission
    }

    func refundAdmission(_ admissionID: String) async throws -> Admission {
        try await query(Documents.refund, variables: ["admissionId": .string(admissionID)], as: RefundResponse.self).refundAdmission.admission
    }

    // MARK: Tips

    func tipQuote(personID: UUID, amountCents: Int) async throws -> ClipTipQuote {
        let response = try await query(Documents.tipQuote,
            variables: ["id": .string(personID.uuidString), "amount": .int(amountCents)], as: QuoteResponse.self)
        guard let quote = response.people.person?.tipping?.quote else { throw ClipError.tipAmount }
        return quote
    }

    func startTip(personID: UUID, amountCents: Int) async throws -> TipPurchase {
        try await query(Documents.startTip,
            variables: ["personId": .string(personID.uuidString), "amount": .int(amountCents)], as: StartTipResponse.self).startTip
    }

    func confirmTip(tipID: String) async throws -> ClipTip {
        try await query(Documents.confirmTip, variables: ["id": .string(tipID)], as: ConfirmTipResponse.self).confirmTip.tip
    }

    private func query<T: Decodable & Sendable>(_ document: String, variables: [String: GraphQLValue], as type: T.Type) async throws -> T {
        try await client.graphQL(document, variables: variables, as: type, decoder: .hotMess)
    }

    // MARK: Response shapes

    private struct PersonResponse: Decodable, Sendable {
        struct People: Decodable, Sendable { let person: ClipPerformer? }
        let people: People
    }
    private struct VenueResponse: Decodable, Sendable {
        struct Venues: Decodable, Sendable { let venue: ClipVenue? }
        let venues: Venues
    }
    private struct EventResponse: Decodable, Sendable {
        struct Events: Decodable, Sendable { let event: ClipEvent? }
        let events: Events
    }
    private struct PurchaseResponse: Decodable, Sendable { let buyCover: CoverPurchase }
    private struct Payload: Decodable, Sendable { let admission: Admission }
    private struct ConfirmResponse: Decodable, Sendable { let confirmCover: Payload }
    private struct RefundResponse: Decodable, Sendable { let refundAdmission: Payload }
    private struct QuoteResponse: Decodable, Sendable {
        struct People: Decodable, Sendable {
            struct Person: Decodable, Sendable {
                struct Tipping: Decodable, Sendable { let quote: ClipTipQuote? }
                let tipping: Tipping?
            }
            let person: Person?
        }
        let people: People
    }
    private struct StartTipResponse: Decodable, Sendable { let startTip: TipPurchase }
    private struct TipPayload: Decodable, Sendable { let tip: ClipTip }
    private struct ConfirmTipResponse: Decodable, Sendable { let confirmTip: TipPayload }

    enum Documents {
        static let person = """
        query ClipPerformer($id: ID!) {
          people { person(id: $id) { id name tipping {
            currency minimumCents maximumCents presetCents options { name isInApp url }
          } } }
        }
        """
        static let admission = """
        id status night total { cents currency } quantity tier kind is_refundable: isRefundable
        pass_secret: passSecret scan_count: scanCount checked_in_at: checkedInAt
        profile { id name avatar_url: avatarUrl } venue { id name photo_url: photoUrl } event { id name }
        """
        static let charge = """
        amount { cents currency } fee { cents currency } total { cents currency }
        night from until payable payment_mechanisms: paymentMechanisms
        tiers { id name amount { cents currency } total { cents currency } description }
        """
        static let venueFields = """
        id name description
        tickets { cover { cover_charge: charge { \(charge) } viewer_admission: viewerAdmission { \(admission) } } }
        """
        static let venue = """
        query ClipVenue($id: ID!) {
          venues { venue(id: $id) { \(venueFields) } }
        }
        """
        static let event = """
        query ClipEvent($id: ID!) {
          events { event(id: $id) {
            id name startAt endAt description
            venue { venue { \(venueFields) } }
          } }
        }
        """
        static let purchaseFields = """
        admission { \(admission) } provider
        payment_intent_client_secret: paymentIntentClientSecret publishable_key: publishableKey
        stripe_account_id: stripeAccountId square_application_id: squareApplicationId
        square_location_id: squareLocationId
        """
        static let buyCover = """
        mutation ClipBuyCover($venueId: ID!, $quantity: Int, $tier: String) {
          buyCover(input: {venueId: $venueId, quantity: $quantity, tier: $tier}) { \(purchaseFields) }
        }
        """
        static let confirmCover = """
        mutation ClipConfirmCover($admissionId: ID!) {
          confirmCover(input: {admissionId: $admissionId}) { admission { \(admission) } }
        }
        """
        static let refund = """
        mutation ClipRefund($admissionId: ID!) {
          refundAdmission(input: {admissionId: $admissionId}) { admission { \(admission) } }
        }
        """
        static let tipFields = "id status amount { cents currency } fee { cents currency } total { cents currency }"
        static let tipQuote = """
        query ClipTipQuote($id: ID!, $amount: Int!) {
          people { person(id: $id) { tipping { quote(amountCents: $amount) {
            amount { cents currency } fee { cents currency } total { cents currency }
          } } } }
        }
        """
        static let startTip = """
        mutation ClipStartTip($personId: ID!, $amount: Int!) {
          startTip(input: {personId: $personId, amountCents: $amount}) {
            tip { \(tipFields) } provider paymentIntentClientSecret publishableKey stripeAccountId squareApplicationId
          }
        }
        """
        static let confirmTip = """
        mutation ClipConfirmTip($id: ID!) { confirmTip(input: {tipId: $id}) { tip { \(tipFields) } } }
        """
    }
}

// MARK: - Models

struct ClipDetails: Sendable {
    let venue: ClipVenue?
    let event: ClipEvent?
    var performer: ClipPerformer? = nil

    /// Tonight's cover at the venue the link points at (an event's venue for event links).
    var coverCharge: CoverCharge? { venue?.tickets?.cover?.coverCharge }
    /// A pass this person already holds for tonight.
    var viewerPass: Admission? {
        guard let pass = venue?.tickets?.cover?.viewerAdmission, pass.isPaid else { return nil }
        return pass
    }
}

struct ClipVenue: Decodable, Sendable {
    let id: UUID
    let name: String
    let description: String?
    let tickets: TicketsMixin?
}

struct ClipEvent: Decodable, Sendable {
    struct Venue: Decodable, Sendable { let venue: ClipVenue? }
    let id: UUID
    let name: String
    let startAt: Date
    let endAt: Date?
    let description: String?
    let venue: Venue?
}

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

        var acceptsInApp: Bool { options.contains(where: \.isInApp) }
        var amounts: ClipTipAmounts {
            ClipTipAmounts(presetCents: presetCents, minimumCents: minimumCents, maximumCents: maximumCents, currency: currency)
        }
    }
    let id: UUID
    let name: String?
    let tipping: Tipping?

    var displayName: String { name ?? "this performer" }
    var firstName: String { name?.firstNameForDisplay ?? "them" }
}

struct ClipTipQuote: Decodable, Sendable {
    let amount: Money
    let fee: Money
    let total: Money
}

struct ClipTip: Decodable, Sendable {
    let id: String
    let status: String
    let amount: Money
    let fee: Money
    let total: Money
    var isPaid: Bool { status == "PAID" }
}

struct TipPurchase: Decodable, Sendable {
    let tip: ClipTip
    let provider: String
    let paymentIntentClientSecret: String?
    let publishableKey: String?
    let stripeAccountId: String?
    let squareApplicationId: String?
}

enum ClipError: LocalizedError {
    case unavailable, missingIdentity, tipAmount, payInApp, applePayUnavailable
    var errorDescription: String? {
        switch self {
        case .unavailable: "This isn't available right now."
        case .missingIdentity: "Apple couldn't complete your sign-in. Please try again."
        case .tipAmount: "That tip amount isn't available."
        case .payInApp: "This venue takes payments in the Hot Mess app. Get the app to pay here."
        case .applePayUnavailable: "Apple Pay isn't set up on this device."
        }
    }
}
