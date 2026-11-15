import Foundation

/// A venue's lobby cover poster (`/cover/<code>`, `GET /v1/cover/:code`, api
/// doc/DIGITAL_COVER_CHARGE.md "Cover poster"): the venue the code names and
/// the night it sells right now. The clip opens the venue's landing and goes
/// straight to paying tonight's cover; when nothing is on tonight it says what
/// the next night is. Decoded with `convertFromSnakeCase`. Pure Foundation so
/// `Scripts/test-app-clip.sh` can check it.
struct ClipCoverPoster: Decodable, Equatable, Sendable {
    struct Venue: Decodable, Equatable, Sendable {
        let id: UUID
        let name: String
        let path: String
    }

    struct Night: Decodable, Equatable, Sendable {
        struct Event: Decodable, Equatable, Sendable {
            let name: String?
            let `public`: Bool
        }
        let night: String
        let tonight: Bool
        let event: Event?
        let cover: ClipOffer.Cover?
    }

    let code: String
    let venue: Venue
    let tonight: Night
    let next: Night?

    /// The venue's own link, which the clip loads as if it had been opened.
    var venueLink: ClipLink? {
        URL(string: "https://hotmess.social/venues/\(venue.id.uuidString.lowercased())").flatMap(ClipLink.init(url:))
    }

    /// Whether to open the checkout as soon as the venue shows: tonight's
    /// cover can be paid here.
    var opensCheckout: Bool {
        tonight.cover?.payable == true
    }

    /// "Nothing on tonight" and the next night, for the landing; nil when
    /// something is on tonight.
    var nextNightNotice: String? {
        guard let next else { return nil }
        var parts = ["Next: \(ClipCoverPoster.dayLabel(next.night))"]
        if let name = next.event?.name { parts.append(name) }
        if let cover = next.cover {
            parts.append(String(format: "$%@ cover", cover.amountCents % 100 == 0
                ? "\(cover.amountCents / 100)" : String(format: "%.2f", Double(cover.amountCents) / 100)))
        }
        return "Nothing's on tonight. " + parts.joined(separator: " · ")
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// "Fri, Nov 20" for a night's ISO date, as that calendar day.
    static func dayLabel(_ iso: String) -> String {
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.timeZone = TimeZone(identifier: "UTC")
        parse.dateFormat = "yyyy-MM-dd"
        guard let date = parse.date(from: iso) else { return iso }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "EEE, MMM d"
        return format.string(from: date)
    }
}
