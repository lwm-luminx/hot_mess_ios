import AudienceCore
import Foundation

/// Authenticated reads and the two payments the clip takes. Same audience
/// endpoint and ban checks as Hot Mess; every call here needs a session.
struct ClipAPI: Sendable {
    let client: AudienceSession

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

    func startTip(personID: UUID, amountCents: Int, showFirstName: Bool) async throws -> TipPurchase {
        try await query(Documents.startTip,
            variables: ["personId": .string(personID.uuidString), "amount": .int(amountCents), "showFirstName": .bool(showFirstName)],
            as: StartTipResponse.self).startTip
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
        mutation ClipStartTip($personId: ID!, $amount: Int!, $showFirstName: Boolean) {
          startTip(input: {personId: $personId, amountCents: $amount, showFirstName: $showFirstName}) {
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

// MARK: - Guest checkout

/// Cover and tips before sign-in (`POST /v1/clip/covers`, `/v1/clip/tips` and
/// their `confirm`, audience_kit_api doc/APP_CLIP_CHECKOUT.md). No session:
/// `host` picks the audience and the claim token is the key to the purchase.
struct ClipGuestAPI: Sendable {
    let client: AudienceSession

    private var host: String? { client.configuration.host }

    func startCover(venueID: UUID, tier: String?, quantity: Int = 1) async throws -> GuestStart<GuestAdmission> {
        var body: [String: GraphQLValue] = ["venue_id": .string(venueID.uuidString.lowercased()), "quantity": .int(quantity)]
        if let tier { body["tier"] = .string(tier) }
        return try await post("/v1/clip/covers", body)
    }

    func confirmCover(id: String, claimToken: String) async throws -> GuestAdmission {
        let response: AdmissionPayload = try await post("/v1/clip/covers/\(id)/confirm", ["claim_token": .string(claimToken)])
        return response.admission
    }

    func startTip(personID: UUID, amountCents: Int, note: String?, showFirstName: Bool) async throws -> GuestStart<GuestTip> {
        var body: [String: GraphQLValue] = [
            "person_id": .string(personID.uuidString.lowercased()), "amount_cents": .int(amountCents),
            "show_first_name": .bool(showFirstName)
        ]
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { body["note"] = .string(note) }
        return try await post("/v1/clip/tips", body)
    }

    func confirmTip(id: String, claimToken: String) async throws -> GuestTip {
        let response: TipPayload = try await post("/v1/clip/tips/\(id)/confirm", ["claim_token": .string(claimToken)])
        return response.tip
    }

    private struct AdmissionPayload: Decodable, Sendable { let admission: GuestAdmission }
    private struct TipPayload: Decodable, Sendable { let tip: GuestTip }

    private func post<T: Decodable & Sendable>(_ path: String, _ body: [String: GraphQLValue]) async throws -> T {
        var body = body
        if let host { body["host"] = .string(host) }
        let data = try await client.data(for: APIRequest(method: "POST", path: path,
            body: try JSONEncoder().encode(body), authenticated: false))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}

/// What starting a guest cover or tip answers: the pending record, its claim
/// token (sent once) and the Stripe checkout on the connected account.
struct GuestStart<Record: Decodable & Sendable>: Decodable, Sendable {
    let claimToken: String
    let provider: String?
    let paymentIntentClientSecret: String?
    let publishableKey: String?
    let stripeAccountId: String?
    let record: Record

    private enum CodingKeys: String, CodingKey {
        case claimToken, provider, paymentIntentClientSecret, publishableKey, stripeAccountId, admission, tip
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        claimToken = try container.decode(String.self, forKey: .claimToken)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        paymentIntentClientSecret = try container.decodeIfPresent(String.self, forKey: .paymentIntentClientSecret)
        publishableKey = try container.decodeIfPresent(String.self, forKey: .publishableKey)
        stripeAccountId = try container.decodeIfPresent(String.self, forKey: .stripeAccountId)
        record = try container.decodeIfPresent(Record.self, forKey: .admission)
            ?? container.decode(Record.self, forKey: .tip)
    }
}

/// A guest's cover as the clip endpoints send it (cents and lower-case status).
struct GuestAdmission: Decodable, Sendable {
    struct Venue: Decodable, Sendable { let id: String?; let name: String? }
    let id: String
    let status: String
    let night: String
    let quantity: Int?
    let tier: String?
    let totalCents: Int
    let currency: String?
    let passSecret: String?
    let venue: Venue?

    /// The pass the clip shows. A guest's isn't refundable from the clip:
    /// refunds go through the member API once it's claimed.
    var admission: Admission {
        Admission(id: id, status: AdmissionStatus(rawValue: status.uppercased()) ?? .unknown, night: night,
                  total: Money(cents: totalCents, currency: currency ?? "usd"), isRefundable: false,
                  passSecret: passSecret, venueID: venue?.id.flatMap(UUID.init(uuidString:)),
                  venueName: venue?.name ?? "", quantity: quantity ?? 1, tier: tier, kind: .cover)
    }
}

/// A guest's tip as the clip endpoints send it.
struct GuestTip: Decodable, Sendable {
    let id: String
    let status: String
    let amountCents: Int
    let feeCents: Int?
    let totalCents: Int
    let currency: String?

    var tip: ClipTip {
        let currency = currency ?? "usd"
        return ClipTip(id: id, status: status.uppercased(), amount: Money(cents: amountCents, currency: currency),
                       fee: Money(cents: feeCents ?? (totalCents - amountCents), currency: currency),
                       total: Money(cents: totalCents, currency: currency))
    }
}

extension ClipOffer.Cover {
    var total: Money { Money(cents: totalCents, currency: currency) }
    var fee: Money { Money(cents: feeCents, currency: currency) }
}

extension ClipOffer.Tier {
    func total(_ fallback: String) -> Money { Money(cents: totalCents, currency: currency ?? fallback) }
    func fee(_ fallback: String) -> Money {
        Money(cents: feeCents ?? (totalCents - amountCents), currency: currency ?? fallback)
    }
}

extension ClipOffer.Tipping.Quote {
    var amount: Money { Money(cents: amountCents, currency: currency) }
    var fee: Money { Money(cents: feeCents, currency: currency) }
    var total: Money { Money(cents: totalCents, currency: currency) }
}
