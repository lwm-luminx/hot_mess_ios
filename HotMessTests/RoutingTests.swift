//
//  RoutingTests.swift
//  HotMessTests
//

import CoreLocation
import Foundation
import MapKit
import Testing

@testable import HotMess

@Suite("Deep links")
struct DeepLinkTests {
    private let id = UUID(uuidString: "8B4F1B60-9A5D-4D0E-9B3F-2C6B3E5D8A11")!

    @Test("Reads the custom scheme, where the type is the host")
    func customScheme() throws {
        let url = try #require(URL(string: "hotmess://venues/\(id.uuidString)"))

        #expect(DeepLink.route(for: url) == .venue(id))
    }

    @Test("Reads a universal link, where the type is the first path component")
    func universalLink() throws {
        let url = try #require(URL(string: "https://hotmess.social/events/\(id.uuidString)"))

        #expect(DeepLink.route(for: url) == .event(id))
    }

    @Test("Handles lower-cased identifiers, which is how the app shares them")
    func lowercasedIdentifier() throws {
        let url = try #require(
            URL(string: "https://www.hotmess.social/people/\(id.uuidString.lowercased())")
        )

        #expect(DeepLink.route(for: url) == .person(id))
    }

    /// The original indexed `pathComponents[1]` and `[2]` and force-unwrapped
    /// the `UUID`, so each of these took the app down on open.
    @Test(
        "Returns nil rather than crashing on a link it doesn't recognise",
        arguments: [
            "hotmess://",
            "hotmess://venues",
            "hotmess://venues/not-a-uuid",
            "https://hotmess.social/",
            "https://hotmess.social/about",
            "https://hotmess.social/venues/",
            "https://hotmess.social/unknown/8B4F1B60-9A5D-4D0E-9B3F-2C6B3E5D8A11",
        ]
    )
    func malformed(link: String) throws {
        let url = try #require(URL(string: link))

        #expect(DeepLink.route(for: url) == nil)
    }

    @Test("Opens a room's chat from its link, as a push about a room the user left carries")
    func chatLinks() throws {
        let venue = try #require(URL(string: "https://hotmess.social/venues/\(id.uuidString.lowercased())/chat"))
        let locale = try #require(URL(string: "https://hotmess.social/locales/\(id.uuidString.lowercased())/chat"))
        let scheme = try #require(URL(string: "hotmess://venues/\(id.uuidString)/chat"))

        #expect(DeepLink.destination(for: venue) == .venueChat(id))
        #expect(DeepLink.destination(for: locale) == .localeChat(id))
        #expect(DeepLink.destination(for: scheme) == .venueChat(id))
        // The venue itself, without `/chat`, is still the venue.
        #expect(DeepLink.destination(for: URL(string: "https://hotmess.social/venues/\(id.uuidString)")) == .route(.venue(id)))
        // Neither a locale nor its chat without an ID leads anywhere.
        #expect(DeepLink.destination(for: URL(string: "https://hotmess.social/locales/\(id.uuidString)")) == nil)
        #expect(DeepLink.destination(for: URL(string: "https://hotmess.social/locales/nope/chat")) == nil)
        #expect(DeepLink.destination(for: URL(string: "https://hotmess.social/events/\(id.uuidString)/chat")) == .route(.event(id)))
    }

    @Test("A chat push's url opens its room, and isn't a Ping")
    func chatPush() throws {
        let push = try #require(PingNotification(userInfo: [
            "kind": "recent_chat", "room_id": id.uuidString, "message_id": UUID().uuidString,
            "url": "https://hotmess.social/venues/\(id.uuidString.lowercased())/chat",
        ]))

        #expect(DeepLink.destination(for: push.url) == .venueChat(id))
        #expect(!push.isPing)
    }

    @Test("A karaoke singer's up-next push opens the venue's chat room")
    func singerUpNextPush() throws {
        let push = try #require(PingNotification(userInfo: [
            "kind": "singer_up_next", "room_id": id.uuidString.lowercased(), "request_id": UUID().uuidString,
            "url": "https://hotmess.social/venues/\(id.uuidString.lowercased())/chat",
        ]))

        #expect(DeepLink.destination(for: push.url) == .venueChat(id))
        #expect(!push.isPing)
    }

    @Test("Keeps a share link's signed expiry, with the host and path it was signed for")
    func expiringLink() throws {
        let url = try #require(
            URL(string: "https://hotmess.social/venues/\(id.uuidString.lowercased())?e=s44we8.AbCdEf_-01234567")
        )
        let link = try #require(DeepLink.expiringLink(for: url))

        #expect(link.route == .venue(id))
        #expect(link.host == "hotmess.social")
        #expect(link.path == "/venues/\(id.uuidString.lowercased())")
        #expect(link.token == "s44we8.AbCdEf_-01234567")
        // It's still the venue to any caller that doesn't check expiries.
        #expect(DeepLink.destination(for: url) == .route(.venue(id)))
    }

    @Test("A share link from before expiries, or a link that isn't a record, doesn't expire")
    func linkWithoutExpiry() throws {
        let older = try #require(URL(string: "https://hotmess.social/events/\(id.uuidString)"))
        let blank = try #require(URL(string: "https://hotmess.social/events/\(id.uuidString)?e="))
        let ping = try #require(URL(string: "https://hotmess.social/pings/ping-1?e=s44we8.sig"))

        #expect(DeepLink.expiringLink(for: older) == nil)
        #expect(DeepLink.expiringLink(for: blank) == nil)
        #expect(DeepLink.expiringLink(for: ping) == nil)
    }

    @Test("Reads a share link's expiry from its token, without the network")
    func expiryDecode() throws {
        // 1_700_000_000 in base 36.
        let link = ExpiringLink(route: .venue(id), host: "hotmess.social", path: "/venues/x", token: "s44we8.AbCdEf_-01234567")

        #expect(link.expiresAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(link.hasExpired(at: Date(timeIntervalSince1970: 1_800_000_000)))
        #expect(!link.hasExpired(at: Date(timeIntervalSince1970: 1_600_000_000)))
        #expect(ExpiringLink.expiry(of: "S44WE8.AbCdEf_-01234567") == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Leaves a token it can't read to the API rather than calling it expired")
    func unreadableExpiry() {
        let link = ExpiringLink(route: .venue(id), host: nil, path: "/venues/x", token: "not!base36.sig")

        #expect(link.expiresAt == nil)
        #expect(!link.hasExpired())
        #expect(ExpiringLink.expiry(of: "s44we8") == nil)
    }

    @Test("A song request's now-playing push opens the venue's chat room")
    func songRequestPlayingPush() throws {
        let push = try #require(PingNotification(userInfo: [
            "kind": "song_request_playing", "room_id": id.uuidString.lowercased(), "request_id": UUID().uuidString,
            "url": "https://hotmess.social/venues/\(id.uuidString.lowercased())/chat",
        ]))

        #expect(DeepLink.destination(for: push.url) == .venueChat(id))
        #expect(!push.isPing)
    }

    @Test("Routes each destination to the tab that owns it")
    func tabForRoute() {
        #expect(AppRoute.karaokeList(id).tab == .venues)
        #expect(AppRoute.venue(id).tab == .venues)
        #expect(AppRoute.event(id).tab == .events)
        #expect(AppRoute.person(id).tab == .people)
    }
}

@Suite("Formatting")
struct FormattingTests {
    @Test("Produces something for any distance, and scales with it")
    func distanceScales() {
        let near = DistanceFormat.string(fromMetres: 120)
        let far = DistanceFormat.string(fromMetres: 8_046)

        #expect(near.isEmpty == false)
        #expect(far.isEmpty == false)
        #expect(near != far)
    }

    /// The old formatter divided feet by 5,280 and then labelled the result
    /// "m", so half a mile printed as "0.5 m".
    @Test("Never labels a long distance with a bare metre abbreviation")
    func longDistanceUnitIsNotAmbiguous() {
        let text = DistanceFormat.string(fromMetres: 8_046) // ~5 miles

        // Road usage switches to kilometres or miles at this range, so a bare
        // metre suffix would mean the value and the unit disagree.
        #expect(text.hasSuffix(" m") == false)
    }

    @Test("Takes at most two initials and upper-cases them")
    func initials() {
        #expect("Rick Mark".initialsForDisplay == "RM")
        #expect("ada lovelace king".initialsForDisplay == "AL")
        #expect("Cher".initialsForDisplay == "C")
        #expect("".initialsForDisplay.isEmpty)
    }

    @Test("Falls back to the whole string when there is no space")
    func firstName() {
        #expect("Rick Mark".firstNameForDisplay == "Rick")
        #expect("Cher".firstNameForDisplay == "Cher")
    }
}

@Suite("Geometry")
struct GeometryTests {
    @Test("Frames a GeoJSON polygon, reading coordinates as longitude-first")
    func polygonRegion() throws {
        let polygon = GeoPolygon(coordinates: [[
            [-122.42, 37.77], [-122.40, 37.77], [-122.40, 37.78], [-122.42, 37.78], [-122.42, 37.77],
        ]])

        let region = try #require(polygon.region)

        #expect(abs(region.center.latitude - 37.775) < 0.0001)
        #expect(abs(region.center.longitude - (-122.41)) < 0.0001)
        #expect(region.span.latitudeDelta > 0)
    }

    @Test("Ignores a polygon with no rings")
    func emptyPolygon() {
        #expect(GeoPolygon(coordinates: []).region == nil)
        #expect(GeoPolygon(coordinates: []).exteriorCoordinates.isEmpty)
    }

    @Test("Skips malformed coordinate pairs instead of trapping")
    func shortPair() {
        let polygon = GeoPolygon(coordinates: [[[-122.42], [-122.40, 37.77]]])

        #expect(polygon.exteriorCoordinates.count == 1)
    }
}

@Suite("Facebook connection prompt")
struct FacebookPromptTests {
    @Test("Tracks whether the user has been prompted for Facebook on ping and chat")
    @MainActor
    func promptedFlags() {
        let model = AppModel.shared
        UserDefaults.standard.removeObject(forKey: "hasPromptedFacebookOnPing")
        UserDefaults.standard.removeObject(forKey: "hasPromptedFacebookOnChat")

        #expect(!model.hasPromptedFacebookOnPing)
        #expect(!model.hasPromptedFacebookOnChat)

        model.hasPromptedFacebookOnPing = true
        #expect(model.hasPromptedFacebookOnPing)
        #expect(!model.hasPromptedFacebookOnChat)

        model.hasPromptedFacebookOnChat = true
        #expect(model.hasPromptedFacebookOnChat)

        model.signOut()
        #expect(!model.hasPromptedFacebookOnPing)
        #expect(!model.hasPromptedFacebookOnChat)
    }
}

