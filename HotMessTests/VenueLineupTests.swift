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

    @Test("Karaoke shows on Now and an event's page when signups are taken, there are singers, or a partner runs it")
    func showsKaraoke() {
        let host = entry("b", role: .host, state: .on, person: hostID)
        let singer = entry("s", role: .singer, state: .upcoming)
        let lineup = { (entries: [AudienceKit.LineupEntry], window: KaraokeWindow?, session: VenueKaraoke?) in
            VenueLineup(venueID: "v", venueName: "The Stud", entries: entries, karaoke: window, karaokeSession: session)
        }
        #expect(lineup([host], KaraokeWindow(permitted: true, open: true, host: host), nil).showsKaraoke)
        #expect(lineup([host, singer], KaraokeWindow(permitted: false, open: false), nil).showsKaraoke)
        #expect(lineup([host], nil, VenueKaraoke(provider: "karafun", providerName: "KaraFun", joinUrl: "https://kf.io/x")).showsKaraoke)
        #expect(!lineup([host], KaraokeWindow(permitted: false, open: false), nil).showsKaraoke)
        #expect(!lineup([host], nil, VenueKaraoke(provider: "audiencekit")).showsKaraoke)
        #expect(!lineup([host], nil, nil).showsKaraoke)
    }

    @Test("Song requests show when the venue takes them, or the viewer still has one waiting or playing")
    func showsSongRequests() {
        let host = entry("b", role: .host, state: .on, person: hostID)
        let lineup = { (window: SongRequestWindow?) in
            VenueLineup(venueID: "v", venueName: "The Stud", entries: [host], songRequests: window)
        }
        let waiting = SongRequest(id: "q1", kind: .song, title: "Toxic", mine: true, state: .queued)
        let played = SongRequest(id: "q2", kind: .song, title: "Believe", mine: true, state: .done)
        #expect(lineup(SongRequestWindow(permitted: true, open: false, closedReason: "Requests open when a DJ is on"))
            .showsSongRequests)
        #expect(lineup(SongRequestWindow(permitted: false, open: false, mine: [waiting])).showsSongRequests)
        #expect(!lineup(SongRequestWindow(permitted: false, open: false, mine: [played])).showsSongRequests)
        #expect(!lineup(nil).showsSongRequests)
    }

    @Test("Counts the requests ahead of the viewer's and lists theirs newest first")
    func songQueue() {
        let playing = SongRequest(id: "q1", kind: .song, title: "Dancing Queen", state: .up)
        let other = SongRequest(id: "q2", kind: .song, title: "Believe")
        let mine = SongRequest(id: "q3", kind: .song, title: "Toxic", mine: true)
        let earlier = SongRequest(id: "q0", kind: .song, title: "Waterloo", mine: true, state: .skipped)
        let window = SongRequestWindow(permitted: true, open: true, mine: [earlier, mine], queue: [playing, other, mine])
        let lineup = VenueLineup(venueID: "v", venueName: "The Stud", entries: [], songRequests: window)

        #expect(window.playing?.id == "q1")
        #expect(window.requestsBefore(mine) == 2)
        #expect(window.requestsBefore(earlier) == nil)
        #expect(lineup.mySongRequests.map(\.id) == ["q3", "q0"])
        #expect(!lineup.showsKaraoke)
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

    @Test("Decodes the SDK's song window with the viewer's request and the queue")
    func decodesSongWindow() throws {
        let request = """
        { "id": "q1", "kind": "SONG", "title": "Dancing Queen", "artist": "ABBA", "singer": null, "mine": true,
          "state": "UP", "summary": "Dancing Queen by ABBA", "position": 0, "note": "For Bo" }
        """
        let json = """
        { "permitted": true, "open": false, "paused": true, "closedReason": "Requests are paused",
          "mine": { "nodes": [\(request)] }, "queue": { "nodes": [\(request)] } }
        """
        let window = try JSONDecoder().decode(SongRequestWindow.self, from: Data(json.utf8))
        #expect(window.paused && !window.open && window.closedReason == "Requests are paused")
        #expect(window.mine.first?.isSong == true)
        #expect(window.playing?.note == "For Bo")
        #expect(window.mine.first?.state.songStatus == "Playing now")
    }
}
