import Foundation

/// The event's karaoke facet. Session and join link are resolved by the API, including venue control.
struct KaraokeNight: Codable, Hashable, Sendable {
    let provider: String?
    let providerName: String?
    let sessionCode: String?
    let ownSessionCode: String?
    private let joinLink: String?
    /// A sing-along night (provider `sing_along`): no singers, the whole room
    /// sings to the night's playlist with the words on the venue's screens.
    /// False from an API before sing-along.
    let singAlong: Bool

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
        case singAlong = "sing_along"
    }

    init(provider: String?, providerName: String?, sessionCode: String? = nil, ownSessionCode: String? = nil,
         joinLink: String? = nil, singAlong: Bool = false) {
        self.provider = provider
        self.providerName = providerName
        self.sessionCode = sessionCode
        self.ownSessionCode = ownSessionCode
        self.joinLink = joinLink
        self.singAlong = singAlong
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName)
        sessionCode = try container.decodeIfPresent(String.self, forKey: .sessionCode)
        ownSessionCode = try container.decodeIfPresent(String.self, forKey: .ownSessionCode)
        joinLink = try container.decodeIfPresent(String.self, forKey: .joinLink)
        singAlong = try container.decodeIfPresent(Bool.self, forKey: .singAlong) ?? false
    }
}
