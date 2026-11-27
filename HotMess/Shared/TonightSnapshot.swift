//
//  TonightSnapshot.swift
//  HotMess
//
//  Shared with the HotMessWidgets extension. The app writes it into the app
//  group whenever it loads Now or the Pings; the Tonight widget only reads it,
//  so the widget never signs in or calls the API itself.
//

import Foundation

/// What the Tonight widget shows: the next few events (with where they are,
/// for its rotating card and its Going and Ping buttons) and who's in on
/// friends' Pings. Names are as the API gives them (a friend's full name, "First L."
/// for anyone else), and only Pings a friend sent (or the user's own) are kept.
struct TonightSnapshot: Codable, Hashable, Sendable {
    /// Something coming up in the user's city, or at the venue they're in.
    ///
    /// The fields added after the first version are optional so a file the
    /// last version saved still reads.
    struct Event: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var name: String
        /// The venue's name, when it has one.
        var place: String?
        var startsAt: Date
        var endsAt: Date?
        var url: URL?
        /// The venue's street address ("1201 E Pike St, Seattle"), when listed.
        var address: String?
        /// The user said they're going.
        var going: Bool?
        /// The user's own Ping names this event.
        var pinged: Bool?

        init(
            id: String, name: String, place: String? = nil, startsAt: Date, endsAt: Date? = nil, url: URL? = nil,
            address: String? = nil, going: Bool? = nil, pinged: Bool? = nil
        ) {
            self.id = id
            self.name = name
            self.place = place
            self.startsAt = startsAt
            self.endsAt = endsAt
            self.url = url
            self.address = address
            self.going = going
            self.pinged = pinged
        }

        var isGoing: Bool { going ?? false }
        var isPinged: Bool { pinged ?? false }

        /// Where it is, for the widget: "Purr · 1518 11th Ave" (the address
        /// up to its first comma), the venue alone, or the address alone.
        var location: String? {
            let street = address?
                .split(separator: ",", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .flatMap { $0.isEmpty ? nil : $0 }
            switch (place, street) {
            case let (place?, street?) where street != place: return "\(place) · \(street)"
            case let (place?, _): return place
            case let (nil, street): return street
            }
        }

        /// Whether a Ping (which lasts until 5am) can name it at `date`: it's
        /// on now or starts within `window`.
        func isPingable(at date: Date, window: TimeInterval = TonightSnapshot.tonightWindow) -> Bool {
            isOn(at: date) && startsAt < date.addingTimeInterval(window)
        }

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

    /// How far ahead counts as tonight, for the Ping button.
    static let tonightWindow: TimeInterval = 12 * 60 * 60
    /// How long the widget's featured event stays before the next one.
    static let rotation: TimeInterval = 15 * 60

    var updatedAt: Date
    /// The city, for the header ("Tonight in Seattle").
    var localeName: String?
    /// The city's id, for a Ping the widget sends.
    var localeID: String?
    /// The venue the user is in, and who's on there now.
    var venueName: String?
    var onNow: String?
    var events: [Event]
    var pings: [Ping]

    init(
        updatedAt: Date, localeName: String? = nil, localeID: String? = nil, venueName: String? = nil,
        onNow: String? = nil, events: [Event], pings: [Ping]
    ) {
        self.updatedAt = updatedAt
        self.localeName = localeName
        self.localeID = localeID
        self.venueName = venueName
        self.onNow = onNow
        self.events = events
        self.pings = pings
    }

    static let empty = TonightSnapshot(updatedAt: .distantPast, events: [], pings: [])

    /// The events the widget's card takes turns featuring at `date`: those
    /// on tonight (on now, or starting within ``tonightWindow``), else just
    /// the next one, so a Thursday evening never features Sunday's karaoke
    /// ahead of Friday's party. The list under the card has the rest, in order.
    func featuredEvents(at date: Date) -> [Event] {
        let events = current(at: date).events
        let tonight = events.filter { $0.isPingable(at: date) }
        return tonight.isEmpty ? Array(events.prefix(1)) : tonight
    }

    /// The event the widget features at `date`. While more than one is on
    /// tonight it moves on to the next every ``rotation``, counted from a
    /// fixed point so a redraw (after a button, or when the app saves) keeps
    /// the same one up.
    func featuredEvent(at date: Date) -> Event? {
        let events = featuredEvents(at: date)
        guard !events.isEmpty else { return nil }
        let slot = Int((date.timeIntervalSince1970 / Self.rotation).rounded(.down))
        return events[((slot % events.count) + events.count) % events.count]
    }

    /// Whether the card rotates at `date`: more than one event on tonight.
    func rotates(at date: Date) -> Bool { featuredEvents(at: date).count > 1 }

    /// The event the card shows at `date`: the one the user stepped to with
    /// the large widget's previous and next buttons while that lasts (and the
    /// event is still on), else the rotation's.
    func featuredEvent(at date: Date, browsing: TonightBrowse?) -> Event? {
        if let browsing, browsing.until > date,
           let picked = current(at: date).events.first(where: { $0.id == browsing.eventID }) {
            return picked
        }
        return featuredEvent(at: date)
    }

    /// The event `step` places from `featured` among all the events still on
    /// at `date` (soonest first, wrapping around): the previous and next
    /// buttons go through every one, tonight's and later.
    func event(_ step: Int, from featured: Event?, at date: Date) -> Event? {
        let events = current(at: date).events
        guard !events.isEmpty else { return nil }
        let index = featured.flatMap { featured in events.firstIndex { $0.id == featured.id } } ?? 0
        return events[((index + step) % events.count + events.count) % events.count]
    }

    /// The start of the rotation slot after `date`.
    static func nextRotation(after date: Date) -> Date {
        let slot = (date.timeIntervalSince1970 / rotation).rounded(.down) + 1
        return Date(timeIntervalSince1970: slot * rotation)
    }

    /// The same, with `event` changed by `change` (after a button).
    func updating(event id: String, _ change: (inout Event) -> Void) -> TonightSnapshot {
        var copy = self
        if let index = copy.events.firstIndex(where: { $0.id == id }) { change(&copy.events[index]) }
        return copy
    }

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

/// The event the user stepped to with the large widget's previous and next
/// buttons. It holds for ``hold``, then the card goes back to rotating.
struct TonightBrowse: Codable, Hashable, Sendable {
    /// How long a step keeps its event up.
    static let hold: TimeInterval = 30 * 60

    var eventID: String
    var until: Date
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
        if let browseURL { try? FileManager.default.removeItem(at: browseURL) }
    }

    // MARK: - Previous and next

    private static var browseURL: URL? {
        fileURL?.deletingLastPathComponent().appending(path: "tonight-browse.json")
    }

    /// Where the user last stepped the card to, written by the widget itself.
    static func readBrowse() -> TonightBrowse? {
        guard let browseURL, let data = try? Data(contentsOf: browseURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TonightBrowse.self, from: data)
    }

    static func writeBrowse(_ browse: TonightBrowse) {
        guard let browseURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(browse) else { return }
        try? data.write(to: browseURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
