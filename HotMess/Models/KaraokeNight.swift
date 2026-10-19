import Foundation

/// The event's karaoke facet. Session and join link are resolved by the API, including venue control.
struct KaraokeNight: Codable, Hashable, Sendable {
    let provider: String?
    let providerName: String?
    let sessionCode: String?
    let ownSessionCode: String?
    private let joinLink: String?

    var venueControlled: Bool { ownSessionCode == nil }
    /// AudienceKit's own karaoke: no partner session to join; people sign up
    /// to sing from the venue's page or chat, and the host calls them up.
    var isAudienceKit: Bool { provider == "audiencekit" && joinURL == nil }
    /// A partner link is a web destination; never open an arbitrary executable scheme from a response.
    var joinURL: URL? {
        guard let joinLink, let parts = URLComponents(string: joinLink),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
        return parts.url
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case providerName = "provider_name"
        case sessionCode = "session_code"
        case ownSessionCode = "own_session_code"
        case joinLink = "join_url"
    }
}
