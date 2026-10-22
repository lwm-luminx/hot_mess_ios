import AudienceKit
import Foundation

/// Authenticated reads use the same audience endpoint and ban checks as Hot Mess.
struct ClipAPI: CoverPaymentAPI {
    let client: AudienceKitClient

    func details(for link: ClipLink) async throws -> ClipDetails {
        let id = String(link.path.split(separator: "/")[1])
        if link.kind == "people" {
            let response = try await query(Documents.person, variables: ["id": .string(id)], as: PersonResponse.self)
            guard let person = response.people.person else { throw ClipError.unavailable }
            return ClipDetails(venue: nil, event: nil, performer: person)
        }
        if link.path.hasPrefix("/venues/") {
            let response = try await query(Documents.venue, variables: ["id": .string(id)], as: VenueResponse.self)
            guard let venue = response.venues.venue else { throw ClipError.unavailable }
            return ClipDetails(venue: venue, event: nil)
        }
        let response = try await query(Documents.event, variables: ["id": .string(id)], as: EventResponse.self)
        guard let event = response.events.event else { throw ClipError.unavailable }
        return ClipDetails(venue: event.venue?.venue, event: event)
    }

    func buyCover(venueID: UUID, quantity: Int, tier: String?) async throws -> CoverPurchase {
        var variables: [String: GraphQLValue] = ["venueId": .string(venueID.uuidString), "quantity": .int(quantity)]
        if let tier { variables["tier"] = .string(tier) }
        return try await query(Documents.buyCover, variables: variables, as: PurchaseResponse.self).buyCover
    }

    func buyCoatCheck(venueID: UUID, quantity: Int) async throws -> CoverPurchase {
        try await query(Documents.buyCoatCheck, variables: ["venueId": .string(venueID.uuidString), "quantity": .int(quantity)], as: CoatResponse.self).buyCoatCheck
    }

    func payCover(admissionID: String, sourceID: String, verificationToken: String?) async throws -> Admission {
        var variables: [String: GraphQLValue] = ["admissionId": .string(admissionID), "sourceId": .string(sourceID)]
        if let verificationToken { variables["verificationToken"] = .string(verificationToken) }
        return try await query(Documents.payCover, variables: variables, as: PaymentResponse.self).payCover.admission
    }

    func confirmCover(admissionID: String) async throws -> Admission {
        try await query(Documents.confirmCover, variables: ["admissionId": .string(admissionID)], as: ConfirmResponse.self).confirmCover.admission
    }

    func refundAdmission(_ admissionID: String) async throws -> Admission {
        try await query(Documents.refund, variables: ["admissionId": .string(admissionID)], as: RefundResponse.self).refundAdmission.admission
    }

    private func query<T: Decodable & Sendable>(_ document: String, variables: [String: GraphQLValue], as type: T.Type) async throws -> T {
        try await client.graphQL(document, variables: variables, as: type, decoder: .hotMess)
    }

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
    private struct CoatResponse: Decodable, Sendable { let buyCoatCheck: CoverPurchase }
    private struct Payload: Decodable, Sendable { let admission: Admission }
    private struct PaymentResponse: Decodable, Sendable { let payCover: Payload }
    private struct ConfirmResponse: Decodable, Sendable { let confirmCover: Payload }
    private struct RefundResponse: Decodable, Sendable { let refundAdmission: Payload }

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
        static let buyCoatCheck = """
        mutation ClipBuyCoatCheck($venueId: ID!, $quantity: Int) {
          buyCoatCheck(input: {venueId: $venueId, quantity: $quantity}) { \(purchaseFields) }
        }
        """
        static let payCover = """
        mutation ClipPayCover($admissionId: ID!, $sourceId: String!, $verificationToken: String) {
          payCover(input: {admissionId: $admissionId, sourceId: $sourceId, verificationToken: $verificationToken}) { admission { \(admission) } }
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
    }
}

struct ClipDetails: Sendable {
    let venue: ClipVenue?
    let event: ClipEvent?
    var performer: ClipPerformer? = nil
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
enum ClipError: LocalizedError {
    case unavailable, missingIdentity
    var errorDescription: String? {
        switch self {
        case .unavailable: "This venue or event is no longer available."
        case .missingIdentity: "Apple couldn't complete your sign-in. Please try again."
        }
    }
}
