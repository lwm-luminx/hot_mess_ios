//
//  TonightSnapshot.swift
//  HotMess
//
//  Shared with the HotMessWidgets extension. The app writes it into the app
//  group whenever it loads Now or the Pings; the Tonight widget only reads it,
//  so the widget never signs in or calls the API itself.
//

import Foundation

/// What the Tonight widget shows: what's on tonight and who's in on friends'
/// Pings. Names are as the API gives them (a friend's full name, "First L."
/// for anyone else), and only Pings a friend sent (or the user's own) are kept.
struct TonightSnapshot: Codable, Hashable, Sendable {
    /// Something on tonight in the user's city, or at the venue they're in.
    struct Event: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var name: String
        /// The venue's name, when it has one.
        var place: String?
        var startsAt: Date
        var endsAt: Date?
        var url: URL?

        /// Still worth showing at `date`: not over (or, with no end, started
        /// less than 4 hours ago).
        func isOn(at date: Date) -> Bool {
            if let endsAt { return endsAt > date }
            return startsAt.addingTimeInterval(4 * 60 * 60) > date
        }
    }

    /// A friend's Ping, or the user's own.
    struct Ping: Codable, Hashable, Sendable, Identifiable {
        var id: String
        /// The sender's first name, or "You".
        var sender: String
        /// The first pick's name ("Purr"), or nil for "anywhere".
        var place: String?
        /// First names of who's in, oldest first.
        var people: [String]
        var joined: Bool
        var isMine: Bool
        var expiresAt: Date
        var url: URL?

        /// "Sam, Alex +2", or nil when nobody's in yet.
        var peopleLine: String? {
            guard !people.isEmpty else { return nil }
            let shown = people.prefix(2).joined(separator: ", ")
            let more = people.count - 2
            return more > 0 ? "\(shown) +\(more)" : shown
        }

        /// Whether the button can say "I'm in": a friend's, not yet joined.
        var canJoin: Bool { !isMine && !joined }
    }

    var updatedAt: Date
    /// The city, for the header ("Tonight in Seattle").
    var localeName: String?
    /// The venue the user is in, and who's on there now.
    var venueName: String?
    var onNow: String?
    var events: [Event]
    var pings: [Ping]

    static let empty = TonightSnapshot(updatedAt: .distantPast, events: [], pings: [])

    /// As it stands at `date`: ended Pings and events dropped.
    func current(at date: Date) -> TonightSnapshot {
        var copy = self
        copy.pings = pings.filter { $0.expiresAt > date }
        copy.events = events.filter { $0.isOn(at: date) }
        return copy
    }

    /// When the widget should next redraw on its own: the next Ping or event
    /// to end, so it drops off without the app having to run.
    func nextChange(after date: Date) -> Date? {
        let ends = pings.map(\.expiresAt) + events.map { $0.endsAt ?? $0.startsAt.addingTimeInterval(4 * 60 * 60) }
        return ends.filter { $0 > date }.min()
    }
}

/// Reads and writes the snapshot in the app group the app and its widget
/// extension share (`HotMessAppGroup` in each Info.plist).
enum TonightStore {
    /// The Tonight widget's kind, for reloading its timelines.
    static let widgetKind = "HotMessTonight"
    private static let fileName = "tonight.json"

    private static var fileURL: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "HotMessAppGroup") as? String, !group.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return container.appending(path: fileName)
    }

    static func read() -> TonightSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TonightSnapshot.self, from: data)
    }

    /// Saves it; false when there's no app group to save to.
    @discardableResult
    static func write(_ snapshot: TonightSnapshot) -> Bool {
        guard let fileURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        // Readable while the phone is locked, for the Lock Screen widget;
        // the widget hides names there (privacySensitive).
        return (try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
    }

    /// Forgets it, for signing out.
    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
