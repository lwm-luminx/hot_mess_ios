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
    case venueChat(Venue)
    /// Every karaoke singer at a venue tonight, by the venue's ID.
    case karaokeList(UUID)
    /// A venue's chat room branded for the event the user is at there (Now).
    case eventChat(ChatRoom)
    /// A locale's chat room, for people out in it who aren't at a venue.
    case localeChat(AppLocale)

    /// Which tab the route belongs in.
    var tab: AppTab {
        switch self {
        case .venue, .venueChat, .karaokeList: .venues
        case .event: .events
        case .person: .people
        case .localeChat, .eventChat: .now
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

/// Where a link leads: a screen to push, or Now from the top (a Ping, which
/// Now shows; `https://hotmess.social/pings/<id>` is what a Ping's push
/// carries as its `url`).
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
        default: return nil
        }
    }

    /// The share link `url` is, when it carries a signed expiry (`e`). `nil`
    /// for any other link, a share link from before expiries included.
    static func expiringLink(for url: URL) -> ExpiringLink? {
        guard case let .route(route) = destination(for: url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "e" })?.value,
              !token.isEmpty
        else { return nil }

        return ExpiringLink(
            route: route,
            host: url.scheme == "hotmess" ? nil : components.host,
            path: "/" + segments(of: url).prefix(2).joined(separator: "/"),
            token: token
        )
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
        return components.path.split(separator: "/").map(String.init)
    }
}

/// A share link with a signed expiry: `https://<audience web domain>/venues/<uuid>?e=<token>`,
/// where the token is the expiry in Unix seconds, in base 36, then a dot and
/// the API's signature. Only the API can check the signature (`/v1/share`),
/// but the expiry the app reads itself, so a link that's plainly out of date
/// never needs the network. Links from before expiries carry no `e`.
struct ExpiringLink: Hashable, Sendable {
    /// The record the link shares.
    let route: AppRoute
    /// The link's host, which names the audience to `/v1/share`.
    let host: String?
    /// `/venues/<uuid>`, spelt as the link spelt it, which is what was signed.
    let path: String
    /// The `e` query value, as the link carried it.
    let token: String

    /// When the link stops working, or `nil` for a token the app can't read
    /// (which is left to the API to judge).
    var expiresAt: Date? { Self.expiry(of: token) }

    /// Whether the token's own expiry has passed, before asking the API.
    func hasExpired(at date: Date = .now) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= date
    }

    /// The base-36 Unix seconds before the token's dot.
    static func expiry(of token: String) -> Date? {
        guard let dot = token.firstIndex(of: "."),
              let seconds = Int(token[..<dot], radix: 36)
        else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }
}
