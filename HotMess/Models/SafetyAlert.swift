//
//  SafetyAlert.swift
//  HotMess
//

import Foundation

/// "I feel unsafe": an alert the user sent to the staff on shift at the venue
/// they're at (`sendSafetyAlert`, api doc/SAFETY_ALERTS.md). The user sees
/// where it stands and its private thread; how staff closed it never reaches
/// the app.
struct SafetyAlert: Decodable, Hashable, Sendable, Identifiable {
    enum State: String, Decodable, Sendable {
        /// Sent, and nobody on shift has picked it up yet.
        case open = "OPEN"
        /// Someone on shift said they're on it.
        case acknowledged = "ACKNOWLEDGED"
        case closed = "CLOSED"
        /// The user said they're OK now.
        case cancelled = "CANCELLED"
        case unknown

        init(from decoder: any Decoder) throws {
            self = State(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    struct Message: Decodable, Hashable, Sendable, Identifiable {
        let id: String
        let body: String
        let fromStaff: Bool
        let senderName: String
        let createdAt: Date
    }

    struct VenueRef: Decodable, Hashable, Sendable {
        let id: String
        let name: String?
    }

    let id: String
    let state: State
    let place: SafetyPlace?
    let concerns: [SafetyConcern]
    let description: String?
    let summary: String
    let seen: Bool
    let acknowledgedByName: String?
    let acknowledgedAt: Date?
    let escalatedAt: Date?
    let closedAt: Date?
    let supportSharedAt: Date?
    let supportNote: String?
    let createdAt: Date
    let venue: VenueRef
    let messages: [Message]

    /// Still waiting for staff, or picked up: what the waiting screen shows.
    var isActive: Bool { state == .open || state == .acknowledged }

    /// How long nobody may pick it up before the API sends it to the venue's
    /// managers too and the app offers other ways to get help
    /// (`SafetyAlert::ESCALATE_AFTER`).
    static let escalationWindow: TimeInterval = 120

    /// Nobody has picked it up and the window has passed: the "Nobody's
    /// picked it up yet" screen.
    func isUnanswered(at now: Date) -> Bool {
        state == .open && (escalatedAt != nil || now.timeIntervalSince(createdAt) >= Self.escalationWindow)
    }
}

/// Where in the venue the user is (`SafetyAlertPlace`).
enum SafetyPlace: String, CaseIterable, Decodable, Hashable, Identifiable, Sendable {
    case bar = "BAR"
    case danceFloor = "DANCE_FLOOR"
    case restrooms = "RESTROOMS"
    case patio = "PATIO"
    case stage = "STAGE"
    case entrance = "ENTRANCE"
    case unsure = "UNSURE"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bar: String(localized: "Bar")
        case .danceFloor: String(localized: "Dance floor")
        case .restrooms: String(localized: "Restrooms")
        case .patio: String(localized: "Patio")
        case .stage: String(localized: "Near the stage")
        case .entrance: String(localized: "Entrance")
        case .unsure: String(localized: "Not sure")
        }
    }
}

/// What's going on (`SafetyAlertConcern`). Any of them.
enum SafetyConcern: String, CaseIterable, Decodable, Hashable, Identifiable, Sendable {
    case bothering = "BOTHERING"
    case following = "FOLLOWING"
    case intoxicated = "INTOXICATED"
    case unwell = "UNWELL"
    case other = "OTHER"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bothering: String(localized: "Someone's bothering me")
        case .following: String(localized: "Someone's following me")
        case .intoxicated: String(localized: "Someone's had too much")
        case .unwell: String(localized: "I don't feel well")
        case .other: String(localized: "Something else")
        }
    }
}

/// What the user filled in on "Tell staff quietly". Everything is optional.
struct SafetyAlertDraft: Hashable, Sendable {
    var place: SafetyPlace?
    var concerns: Set<SafetyConcern> = []
    var description = ""

    var trimmedDescription: String? {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// Whether "Get help" shows on a venue and whether "Tell staff" is offered:
/// the app places the user there, and someone on shift hears alerts.
struct VenueSafety: Hashable, Sendable {
    var canSend: Bool
    var staffOnShift: Bool
}

/// "Need support?": the emergency number and the crisis and support lines
/// for a region (`Audience.supportResources`).
struct SupportResources: Decodable, Hashable, Sendable {
    struct Line: Decodable, Hashable, Sendable, Identifiable {
        let id: String
        let name: String
        let description: String?
        /// Digits only.
        let phone: String?
        let textNumber: String?
        /// What to text to start, when the line asks for something ("START").
        let textBody: String?
        let url: String?

        var callURL: URL? { phone.flatMap { URL(string: "tel:\($0)") } }

        var textURL: URL? {
            guard let textNumber else { return nil }
            var components = URLComponents()
            components.scheme = "sms"
            components.path = textNumber
            if let textBody { components.queryItems = [URLQueryItem(name: "body", value: textBody)] }
            return components.url
        }

        var websiteURL: URL? { url.flatMap(URL.init(string:)) }

        /// The number written out, so it can be read aloud or dialled from
        /// another phone: "Call 988", "Call 1-866-488-7386 · Text START to 678678".
        var numbers: String {
            var parts: [String] = []
            if let phone { parts.append(String(localized: "Call \(SupportResources.format(phone))")) }
            if let textNumber {
                if let textBody {
                    parts.append(String(localized: "Text \(textBody) to \(textNumber)"))
                } else {
                    parts.append(String(localized: "Text \(SupportResources.format(textNumber))"))
                }
            }
            return parts.joined(separator: " · ")
        }
    }

    /// "Get a ride": a ride app as a plain link (Uber, Lyft). `url` opens
    /// the app, or its site when it isn't installed; `pickupUrl` does the
    /// same with the pickup set once `{latitude}`, `{longitude}` and `{name}`
    /// are filled in.
    struct Ride: Decodable, Hashable, Sendable, Identifiable {
        let id: String
        let name: String
        let url: String
        let pickupUrl: String?

        /// The link for a pickup at `pickup`, or the plain one when there's
        /// no pickup or the app takes none.
        func link(pickup: RidePickup?) -> URL? {
            guard let pickup, let pickupUrl else { return URL(string: url) }
            let filled = pickupUrl
                .replacingOccurrences(of: "{latitude}", with: String(format: "%.6f", pickup.coordinates.latitude))
                .replacingOccurrences(of: "{longitude}", with: String(format: "%.6f", pickup.coordinates.longitude))
                .replacingOccurrences(of: "{name}", with: Self.encode(pickup.name ?? ""))
            return URL(string: filled) ?? URL(string: url)
        }

        private static func encode(_ value: String) -> String {
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        }
    }

    let region: String
    let name: String
    let emergency: String
    /// When someone last checked every line ("2026-10-23"); nil until they
    /// have, and the screen then shows no date.
    let checkedAt: String?
    let lines: [Line]

    var checkedDate: Date? {
        guard let checkedAt else { return nil }
        return try? Date(checkedAt, strategy: Date.ISO8601FormatStyle().year().month().day())
    }

    /// 18664887386 as 1-866-488-7386, 8775658860 as 877-565-8860; short
    /// codes as they are.
    static func format(_ digits: String) -> String {
        let chars = Array(digits)
        switch chars.count {
        case 10:
            return "\(String(chars[0..<3]))-\(String(chars[3..<6]))-\(String(chars[6..<10]))"
        case 11 where chars.first == "1":
            return "1-\(String(chars[1..<4]))-\(String(chars[4..<7]))-\(String(chars[7..<11]))"
        default:
            return digits
        }
    }
}

/// Where "Get a ride" sets the pickup: the venue, or where the phone is.
struct RidePickup: Hashable, Sendable {
    let coordinates: Coordinates
    /// The venue's name, shown as the pickup in the ride app.
    let name: String?
}
