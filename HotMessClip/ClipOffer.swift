import Foundation

/// The share card's `clip` block (`GET /v1/share?view=clip`): what the clip
/// can sell before anyone signs in, tonight's cover or a tip, and whether it
/// can take the payment itself (`guest_checkout`). Decoded with
/// `convertFromSnakeCase`. Pure Foundation so `Scripts/test-app-clip.sh` can
/// check it.
struct ClipOffer: Decodable, Equatable, Sendable {
    let kind: String
    let venueId: UUID?
    let personId: UUID?
    /// The record hides what the clip would sell (a Community event or
    /// performer): sign in first, as before guest checkout.
    let signInRequired: Bool
    let cover: Cover?
    let tipping: Tipping?

    struct Cover: Decodable, Equatable, Sendable {
        let night: String
        let eventId: UUID?
        let amountCents: Int
        let feeCents: Int
        let totalCents: Int
        let currency: String
        let coverFrom: String?
        let coverUntil: String?
        let tiers: [Tier]
        let payable: Bool
        let provider: String?
        let guestCheckout: Bool
        let maxQuantity: Int?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            night = try container.decode(String.self, forKey: .night)
            eventId = try container.decodeIfPresent(UUID.self, forKey: .eventId)
            amountCents = try container.decode(Int.self, forKey: .amountCents)
            totalCents = try container.decode(Int.self, forKey: .totalCents)
            feeCents = try container.decodeIfPresent(Int.self, forKey: .feeCents) ?? (totalCents - amountCents)
            currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "usd"
            coverFrom = try container.decodeIfPresent(String.self, forKey: .coverFrom)
            coverUntil = try container.decodeIfPresent(String.self, forKey: .coverUntil)
            tiers = try container.decodeIfPresent([Tier].self, forKey: .tiers) ?? []
            payable = try container.decodeIfPresent(Bool.self, forKey: .payable) ?? false
            provider = try container.decodeIfPresent(String.self, forKey: .provider)
            guestCheckout = try container.decodeIfPresent(Bool.self, forKey: .guestCheckout) ?? false
            maxQuantity = try container.decodeIfPresent(Int.self, forKey: .maxQuantity)
        }

        private enum CodingKeys: String, CodingKey {
            case night, eventId, amountCents, feeCents, totalCents, currency, coverFrom, coverUntil, tiers
            case payable, provider, guestCheckout, maxQuantity
        }
    }

    /// A `CoverCharge::Tier`.
    struct Tier: Decodable, Equatable, Sendable, Identifiable {
        let id: String
        let name: String
        let description: String?
        let amountCents: Int
        let feeCents: Int?
        let totalCents: Int
        let currency: String?
    }

    struct Tipping: Decodable, Equatable, Sendable {
        let inApp: Bool
        let provider: String?
        let guestCheckout: Bool
        let minimumCents: Int
        let maximumCents: Int
        let presetCents: [Int]
        let noteLength: Int?
        let quotes: [Quote]

        struct Quote: Decodable, Equatable, Sendable {
            let amountCents: Int
            let feeCents: Int
            let totalCents: Int
            let currency: String
        }

        var currency: String { quotes.first?.currency ?? "usd" }

        var amounts: ClipTipAmounts {
            ClipTipAmounts(presetCents: presetCents, minimumCents: minimumCents, maximumCents: maximumCents, currency: currency)
        }

        func quote(for cents: Int) -> Quote? { quotes.first { $0.amountCents == cents } }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            inApp = try container.decodeIfPresent(Bool.self, forKey: .inApp) ?? false
            provider = try container.decodeIfPresent(String.self, forKey: .provider)
            guestCheckout = try container.decodeIfPresent(Bool.self, forKey: .guestCheckout) ?? false
            minimumCents = try container.decodeIfPresent(Int.self, forKey: .minimumCents) ?? 0
            maximumCents = try container.decodeIfPresent(Int.self, forKey: .maximumCents) ?? 0
            presetCents = try container.decodeIfPresent([Int].self, forKey: .presetCents) ?? []
            noteLength = try container.decodeIfPresent(Int.self, forKey: .noteLength)
            quotes = try container.decodeIfPresent([Quote].self, forKey: .quotes) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case inApp, provider, guestCheckout, minimumCents, maximumCents, presetCents, noteLength, quotes
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        venueId = try container.decodeIfPresent(UUID.self, forKey: .venueId)
        personId = try container.decodeIfPresent(UUID.self, forKey: .personId)
        signInRequired = try container.decodeIfPresent(Bool.self, forKey: .signInRequired) ?? false
        cover = try container.decodeIfPresent(Cover.self, forKey: .cover)
        tipping = try container.decodeIfPresent(Tipping.self, forKey: .tipping)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, venueId, personId, signInRequired, cover, tipping
    }

    /// Cover the clip can take with Apple Pay before sign-in.
    var guestCover: (venueID: UUID, cover: Cover)? {
        guard !signInRequired, let venueId, let cover, cover.payable, cover.guestCheckout else { return nil }
        return (venueId, cover)
    }

    /// A tip the clip can take with Apple Pay before sign-in.
    var guestTipping: (personID: UUID, tipping: Tipping)? {
        guard !signInRequired, let personId, let tipping, tipping.inApp, tipping.guestCheckout else { return nil }
        return (personId, tipping)
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
