//
//  VenueLineupTests.swift
//  HotMessTests
//

import AudienceKit
import AudienceKitUI
import Foundation
import Testing

@testable import HotMess

@Suite("Venue lineup")
struct VenueLineupTests {
    private let hostID = "4D9A0C21-8E76-4A5B-B3C2-6F1D8E0A9B33"

    private func entry(_ id: String, role: AudienceKit.LineupEntry.Role?, state: AudienceKit.LineupEntry.State,
                       person: String? = nil) -> AudienceKit.LineupEntry {
        AudienceKit.LineupEntry(id: id, role: role, people: person.map { [.init(id: $0, name: "Trixie")] } ?? [],
                                state: state)
    }

    @Test("The host on now is the lineup's host who's on, else the one taking signups")
    func hostOnNow() {
        let done = entry("a", role: .host, state: .done, person: UUID().uuidString)
        let on = entry("b", role: .host, state: .on, person: hostID)
        let dj = entry("c", role: .dj, state: .on, person: UUID().uuidString)
        #expect(VenueLineup(venueID: "v", venueName: "The Stud", entries: [done, dj, on]).hostOnNow?.id == "b")

        let window = KaraokeWindow(permitted: true, open: true, host: on)
        #expect(VenueLineup(venueID: "v", venueName: "The Stud", entries: [done, dj], karaoke: window).hostOnNow?.id == "b")
        #expect(VenueLineup(venueID: "v", venueName: "The Stud", entries: [done, dj]).hostOnNow == nil)
    }

    @Test("An act opens its first person's page; a singer or a break opens nothing")
    func personID() {
        #expect(entry("b", role: .host, state: .on, person: hostID).personID == UUID(uuidString: hostID))
        #expect(entry("s", role: .singer, state: .upcoming).personID == nil)
        #expect(AudienceKit.LineupEntry(id: "i", kind: .intermission).personID == nil)
        #expect(entry("x", role: .dj, state: .on, person: "not-a-uuid").personID == nil)
    }

    @Test("The host row links to their profiles, not their tip links, and names each for VoiceOver")
    func hostLinks() throws {
        var payload = try #require(JSONSerialization.jsonObject(with: Data(Fixtures.personDetail.utf8)) as? [String: Any])
        payload["profile"] = ["social_links": ["nodes": [
            ["id": UUID().uuidString, "handle": "trixie", "provider": "instagram", "url": "https://instagram.com/trixie"],
            ["id": UUID().uuidString, "handle": "trixie", "provider": "venmo", "url": "https://venmo.com/trixie"],
            ["id": UUID().uuidString, "handle": "nolink", "provider": "facebook"],
            ["id": UUID().uuidString, "handle": "x/y", "provider": "spotify", "url": "https://open.spotify.com/artist/1"],
        ]]]
        let detail = try JSONDecoder.hotMess.decode(PersonDetail.self, from: JSONSerialization.data(withJSONObject: payload))

        let links = HostLink.links(for: detail)
        #expect(links.map(\.url.absoluteString) == ["https://instagram.com/trixie", "https://open.spotify.com/artist/1"])
        #expect(links.map(\.title) == ["Rick Mark on Instagram", "Rick Mark on Spotify"])
        #expect(links.map(\.systemImage) == ["camera", "music.note"])
        #expect(detail.tipLinks.map(\.tipApp) == ["Venmo"])
    }

    @Test("Decodes the SDK's lineup with a singer and the viewer's signup")
    func decodesSDKModels() throws {
        let json = """
        { "id": "s1", "kind": "ACT", "role": "SINGER", "state": "UPCOMING", "startTiming": "NONE",
          "endTiming": "ADVANCE", "people": { "nodes": [] },
          "songRequest": { "id": "r1", "kind": "KARAOKE", "title": "Waterloo", "artist": "ABBA", "singer": "Ada",
                           "mine": true, "state": "QUEUED" } }
        """
        let singer = try JSONDecoder().decode(AudienceKit.LineupEntry.self, from: Data(json.utf8))
        #expect(singer.isSinger)
        #expect(singer.displayName == "Ada")
        #expect(singer.personID == nil)
        #expect(singer.songRequest?.songLine == "Waterloo · ABBA")
    }
}
