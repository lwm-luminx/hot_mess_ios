//
//  SpotifyShareInbox.swift
//  HotMess
//

import Foundation

/// A Spotify song shared to Hot Mess from Spotify's share sheet, waiting for
/// the app to send it to the bar as a song request. The share extension
/// can't sign in or reach the venue's room, so it leaves the link here, in
/// the app group the app and its extensions share (`HotMessAppGroup` in each
/// Info.plist), and the app picks it up when it opens. The app also leaves
/// the venue whose song requests the person last saw open, so the extension
/// can say where it's going. Spotify only ever plays on the person's own
/// account: this carries a link, nothing more.
enum SpotifyShareInbox {
    struct Share: Codable, Equatable {
        var link: String
        var sharedAt: Date
    }

    struct RequestVenue: Codable, Equatable {
        var id: String
        var name: String
        var seenAt: Date
    }

    /// How long a share waits for the app before it's dropped.
    static let shareLifetime: TimeInterval = 60 * 60
    /// How long a venue whose requests were open stays the place a share goes.
    static let venueLifetime: TimeInterval = 6 * 60 * 60

    private static let shareKey = "spotifyShare.pending"
    private static let venueKey = "spotifyShare.requestVenue"

    private static var defaults: UserDefaults? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "HotMessAppGroup") as? String, !group.isEmpty
        else { return nil }
        return UserDefaults(suiteName: group)
    }

    /// The first Spotify link in shared text or a shared URL, or nil.
    static func spotifyLink(in text: String) -> String? {
        let pattern = #"(https?://(open\.spotify\.com|spotify\.link|spotify\.app\.link)/\S+|spotify:(track|playlist|album|artist):[A-Za-z0-9]+)"#
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(text[range])
    }

    /// Keeps a shared link for the app; false when there's no app group.
    @discardableResult
    static func save(_ link: String, now: Date = Date()) -> Bool {
        store(Share(link: link, sharedAt: now), key: shareKey)
    }

    /// The waiting share, removed so it's handled once; nil when there's none
    /// or it waited too long.
    static func take(now: Date = Date()) -> Share? {
        guard let share: Share = load(shareKey) else { return nil }
        defaults?.removeObject(forKey: shareKey)
        return now.timeIntervalSince(share.sharedAt) <= shareLifetime ? share : nil
    }

    static func rememberRequestVenue(id: String, name: String, now: Date = Date()) {
        _ = store(RequestVenue(id: id, name: name, seenAt: now), key: venueKey)
    }

    /// The venue whose song requests the person last saw open, while it's recent.
    static func requestVenue(now: Date = Date()) -> RequestVenue? {
        guard let venue: RequestVenue = load(venueKey) else { return nil }
        return now.timeIntervalSince(venue.seenAt) <= venueLifetime ? venue : nil
    }

    private static func store(_ value: some Encodable, key: String) -> Bool {
        guard let defaults else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return false }
        defaults.set(data, forKey: key)
        return true
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }
}
