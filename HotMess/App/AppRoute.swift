//
//  AppRoute.swift
//  HotMess
//

import Foundation

/// Somewhere in the app that can be linked to.
enum AppRoute: Hashable, Sendable {
    case venue(UUID)
    case event(UUID)
    case person(UUID)
    case ping(UUID, invitation: String?)
    case venueChat(Venue)
    /// Every karaoke singer at a venue tonight, by the venue's ID.
    case karaokeList(UUID)
    /// A venue's chat room branded for the event the user is at there (Now).
    case eventChat(ChatRoom)
    /// A locale's chat room, for people out in it who aren't at a venue.
    case localeChat(AppLocale)
    /// A post and its comments.
    case post(UUID)
    /// Every post on a page, from its section's "See all".
    case posts(PostsSubject, title: String)
    /// A locale's updates feed, from Now.
    case updates(AppLocale)

    /// Which tab the route belongs in.
    var tab: AppTab {
        switch self {
        case .venue, .venueChat, .karaokeList: .venues
        case .event: .events
        case .person: .people
        case .localeChat, .eventChat, .ping, .updates: .now
        case let .posts(subject, _):
            switch subject {
            case .venue: .venues
            case .event: .events
            case .person: .people
            case .locale: .now
            }
        // A post opens wherever it's linked from; a link from outside lands on Now.
        case .post: .now
        }
    }
}

enum AppTab: Hashable, Sendable, CaseIterable {
    case now
    case events
    case venues
    case people
    case me

    var title: String {
        switch self {
        case .now: String(localized: "Now")
        case .events: String(localized: "Events")
        case .venues: String(localized: "Venues")
        case .people: String(localized: "People")
        case .me: String(localized: "Me")
        }
    }

    /// SF Symbols replace the flat 2017 PNG glyphs: they pick up the tint,
    /// adapt to Dark Mode, and scale with Dynamic Type.
    var systemImage: String {
        switch self {
        case .now: "house.fill"
        case .events: "calendar"
        case .venues: "mappin.and.ellipse"
        case .people: "person.2.fill"
        case .me: "person.crop.circle"
        }
    }
}

/// Where a link leads: a screen to push, or Now from the top. A Ping's link
/// (`https://hotmess.social/pings/<id>`, what its push carries as its `url`,
/// or a texted invitation with `?e=<token>`) opens that Ping on Now; a
/// `pings` link without a Ping ID opens Now.
enum DeepLinkDestination: Hashable, Sendable {
    case route(AppRoute)
    case now
    /// A venue's chat room, by the venue's ID (`/venues/<id>/chat`, which a
    /// push about a room the user just left carries): the venue, then its
    /// room once the venue loads.
    case venueChat(UUID)
    /// A locale's chat room, by the locale's ID (`/locales/<id>/chat`): the
    /// room when it's the user's locale now, else Now.
    case localeChat(UUID)
    /// One of the user's safety alerts (`/safety-alerts/<id>`, which the
    /// guest's pushes about it carry): its Get help sheet over any tab.
    case safetyAlert(UUID)
}

/// Parses the app's deep links.
///
/// Handles both `hotmess://venues/<uuid>` and
/// `https://hotmess.social/venues/<uuid>`. The original indexed
/// `pathComponents[1]` and `[2]` and force-unwrapped the result, so any
/// unexpected link crashed the app on open.
enum DeepLink {
    /// Everything the app opens from a link, pushes included.
    static func destination(for url: URL?) -> DeepLinkDestination? {
        guard let url else { return nil }
        let segments = segments(of: url)
        if segments.count >= 3, segments[2] == "chat", let id = UUID(uuidString: segments[1]) {
            switch segments[0] {
            case "venues": return .venueChat(id)
            case "locales": return .localeChat(id)
            default: break
            }
        }
        if segments.count >= 2, segments[0] == "safety-alerts", let id = UUID(uuidString: segments[1]) {
            return .safetyAlert(id)
        }
        if let route = route(for: url) { return .route(route) }
        return segments.first == "pings" ? .now : nil
    }

    /// A screen to push, or `nil` for a link with none (Now, or an unknown one).
    static func route(for url: URL) -> AppRoute? {
        let segments = segments(of: url)
        guard segments.count >= 2, let id = UUID(uuidString: segments[1]) else { return nil }

        switch segments[0] {
        case "venues": return .venue(id)
        case "events": return .event(id)
        case "people": return .person(id)
        case "pings": return .ping(id, invitation: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "e" })?.value)
        case "posts": return .post(id)
        default: return nil
        }
    }

    /// `["venues", "<uuid>"]` for either form of link.
    private static func segments(of url: URL) -> [String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return []
        }

        if url.scheme == "hotmess" {
            // hotmess://venues/<uuid> — the type is the host.
            return [components.host, components.path]
                .compactMap { $0 }
                .flatMap { $0.split(separator: "/").map(String.init) }
        }
        guard components.scheme == "https",
              ["hotmess.social", "www.hotmess.social"].contains(components.host?.lowercased() ?? ""),
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443 else { return [] }
        return components.path.split(separator: "/").map(String.init)
    }
}

/// A share link's `e`. The API's original tokens are the expiry in Unix
/// seconds, in base 36, a dot and a 16-character signature
/// (`s44we8.AbCdEf_-01234567`), so the app can read the expiry itself and
/// skip the network for a link plainly out of date. Attributed tokens
/// (`v2.`, `v3.`, what a signed-in share mints) are opaque: only `/v1/share`
/// can say when they end.
enum ShareLinkToken {
    /// When `token` stops working, or `nil` for one the app can't read.
    static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, !token.hasPrefix("v2."), !token.hasPrefix("v3."),
              (1...10).contains(parts[0].count), parts[0].allSatisfy({ $0.isASCII && ($0.isNumber || $0.isLowercase) }),
              parts[1].count == 16,
              let seconds = Int(parts[0], radix: 36)
        else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// Whether the token's own expiry has passed. `false` for an opaque one.
    static func hasExpired(_ token: String, at date: Date = .now) -> Bool {
        guard let expiry = expiry(of: token) else { return false }
        return expiry <= date
    }
}
