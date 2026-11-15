import Foundation

/// A venue's safety poster, as `GET /v1/safety/posters/<code>` answers it
/// (audience_kit_api doc/SAFETY_ALERTS.md, "Safety posters").
struct ClipSafetyPoster: Decodable, Sendable {
    struct Venue: Decodable, Sendable, Hashable {
        let id: String
        let name: String
    }
    let venue: Venue
    let staffOnShift: Bool
    let places: [String]
    let concerns: [String]
}

/// The alert a guest without the app sent from a poster: what they see of it.
/// Never the outcome or staff notes, which the API doesn't send.
struct ClipSafetyAlert: Decodable, Sendable, Equatable {
    struct Message: Decodable, Sendable, Equatable, Identifiable {
        let id: String
        let body: String
        let fromStaff: Bool
        let senderName: String?
        let createdAt: Date
    }
    let id: String
    let state: String
    let place: String?
    let concerns: [String]
    let description: String?
    let seen: Bool
    let acknowledgedByName: String?
    let supportNote: String?
    let venue: ClipSafetyPoster.Venue
    let staffOnShift: Bool
    let messages: [Message]
    let createdAt: Date
    let escalatesAt: Date?
    let escalatedAt: Date?
    let remindedAt: Date?

    var isActive: Bool { state == "open" || state == "acknowledged" }

    /// The status steps: sent, seen by someone on shift, someone's on it.
    enum Step: Int, Comparable {
        case sent, seen, onIt
        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    var step: Step {
        if state == "acknowledged" || acknowledgedByName != nil { return .onIt }
        return seen ? .seen : .sent
    }

    /// Nobody picked it up in time: offer the other ways to get help.
    var needsOtherHelp: Bool { state == "open" && escalatedAt != nil }
}

struct ClipSafetyAlertResponse: Decodable, Sendable {
    let alert: ClipSafetyAlert
    let guestToken: String?
}

enum ClipSafetyCoding {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func body(_ fields: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: fields)
    }

    /// What the guest typed into the details form, as the API takes it.
    static func details(place: String?, concerns: Set<String>, description: String) -> [String: Any] {
        var fields: [String: Any] = ["concerns": concerns.sorted()]
        if let place { fields["place"] = place }
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { fields["description"] = text }
        return fields
    }

    static func placeTitle(_ place: String) -> String {
        switch place {
        case "bar": "Bar"
        case "dance_floor": "Dance floor"
        case "restrooms": "Restrooms"
        case "patio": "Patio"
        case "stage": "Near the stage"
        case "entrance": "Entrance"
        case "unsure": "Not sure"
        default: place.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func concernTitle(_ concern: String) -> String {
        switch concern {
        case "bothering": "Someone's bothering me"
        case "following": "Someone's following me"
        case "intoxicated": "Someone's had too much"
        case "unwell": "I don't feel well"
        case "other": "Something else"
        default: concern.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

/// The guest token and alert for each poster code, kept on this device only.
/// The token is the only key to the alert; the API keeps just its digest.
struct ClipSafetyStore {
    struct Entry: Codable, Equatable {
        let alertID: String
        let token: String
    }

    var defaults: UserDefaults = .standard

    private func key(_ code: String) -> String { "hotmess.safety-poster.\(code)" }

    func entry(for code: String) -> Entry? {
        defaults.data(forKey: key(code)).flatMap { try? JSONDecoder().decode(Entry.self, from: $0) }
    }

    func save(_ entry: Entry, for code: String) {
        defaults.set(try? JSONEncoder().encode(entry), forKey: key(code))
    }

    func forget(_ code: String) {
        defaults.removeObject(forKey: key(code))
    }
}
