//
//  RoomLineupTests.swift
//  HotMessTests
//

import AudienceKit
import Foundation
import Testing

@testable import HotMess

/// One subscription result, the way the cable hands it on.
private func events(_ room: String) -> [VenueChatConnection.Event] {
    VenueChatConnection.events(from: .result(Data(#"{ "data": { "room": \#(room) } }"#.utf8)))
}

@Suite("The lineup in the event room")
struct RoomLineupTests {
    private let aurora = "4D9A0C21-8E76-4A5B-B3C2-6F1D8E0A9B33"
    private let kiki = "5E0B1D32-9F87-4B6C-84D3-7A2E9F1B0C44"

    private func entry(
        _ id: String,
        kind: AudienceKit.LineupEntry.Kind = .act,
        role: AudienceKit.LineupEntry.Role? = .performer,
        state: AudienceKit.LineupEntry.State = .upcoming,
        people: [String] = []
    ) -> AudienceKit.LineupEntry {
        AudienceKit.LineupEntry(
            id: id, kind: kind, role: role, title: id.capitalized,
            people: people.map { .init(id: $0, name: $0) }, state: state
        )
    }

    @Test("The host leads, then on now, up next, the rest to come, and done acts last; no singers")
    func order() {
        let lineup = VenueLineup(
            venueID: "v", venueName: "The Wildrose",
            entries: [
                entry("opener", role: .dj, state: .done),
                entry("later"),
                entry("next"),
                entry("host", role: .host, state: .on),
                entry("singer", role: .singer, state: .on),
                entry("break", kind: .intermission, role: nil),
                entry("mc", role: .mc, state: .on),
            ],
            upNextID: "next"
        )

        let faces = HereNowLineupFace.faces(for: lineup, presence: nil)
        #expect(faces.map(\.id) == ["host", "mc", "next", "later", "opener"])
        #expect(faces.map(\.status) == [.onNow, .onNow, .upNext, nil, .done])
        #expect(faces.first?.role?.title == "Host")
        #expect(faces.last?.isDone == true)
        // The room hasn't said who's in: no dots.
        #expect(faces.allSatisfy { $0.presence == nil && $0.presenceText == nil })
    }

    @Test("A done host goes with the done acts; an intermission shows only while it's on")
    func doneHostAndBreaks() {
        let lineup = VenueLineup(
            venueID: "v", venueName: "The Wildrose",
            entries: [
                entry("host", role: .host, state: .done),
                entry("break", kind: .intermission, role: nil, state: .on),
                entry("act"),
            ]
        )

        let faces = HereNowLineupFace.faces(for: lineup, presence: [:])
        #expect(faces.map(\.id) == ["break", "act", "host"])
        #expect(faces.first?.isIntermission == true)
        #expect(faces.first?.status == .onNow)
        // An intermission has nobody to reach.
        #expect(faces.first?.presence == nil)
    }

    @Test("An act is in chat if any of its people is, else reachable, else not in chat yet")
    func presence() {
        let duet = entry("duet", people: [aurora, kiki])
        #expect(HereNowLineupFace.presence(of: duet, in: [aurora.lowercased(): .push, kiki.lowercased(): .online]) == .online)
        #expect(HereNowLineupFace.presence(of: duet, in: [kiki.lowercased(): .push]) == .push)
        #expect(HereNowLineupFace.presence(of: duet, in: [:]) == .offline)
        #expect(HereNowLineupFace.presence(of: duet, in: nil) == nil)

        let face = HereNowLineupFace(entry: duet, upNextID: nil, presence: [:])
        #expect(face.presenceText == "Not in chat yet")
        // A duet is one face, with its first two people.
        #expect(face.people.count == 2)
    }

    @Test("VoiceOver reads the act as the lineup does, with whether they're in chat")
    func accessibility() {
        let host = HereNowLineupFace(
            entry: entry("aurora borealis", role: .host, state: .on, people: [aurora]),
            upNextID: nil,
            presence: [aurora.lowercased(): .online]
        )
        #expect(host.accessibilityLabel == "Aurora Borealis, Host, on now, in chat now")
        #expect(host.presenceText == "In chat now")
        #expect(host.personID == UUID(uuidString: aurora))
    }

    @Test("A set time shows only for a hard start")
    func setTime() {
        let start = Date(timeIntervalSince1970: 1_791_590_400)
        let hard = AudienceKit.LineupEntry(id: "a", role: .host, startTiming: .hard, endTiming: .close, startsAt: start)
        let soft = AudienceKit.LineupEntry(id: "b", role: .host, startTiming: .soft, startsAt: start)
        let utc = TimeZone(identifier: "UTC")!
        #expect(HereNowLineupFace.setTime(of: hard, timeZone: utc)?.hasSuffix("close") == true)
        #expect(HereNowLineupFace.setTime(of: soft, timeZone: utc) == nil)
    }

    @Test("The Small talk line names the venue, the lineup in chat and a friend, then the count")
    func summaryLine() {
        #expect(RoomSummary.line(venue: "The Wildrose", lineupInChat: 3, friend: "Jordan", count: 23)
            == "The Wildrose, 3 from tonight's lineup and Jordan · 23 here")
        #expect(RoomSummary.line(venue: "The Wildrose", lineupInChat: 2, friend: nil, count: 9)
            == "The Wildrose and 2 from tonight's lineup · 9 here")
        #expect(RoomSummary.line(venue: "The Wildrose", lineupInChat: 0, friend: "Jordan", count: 23)
            == "The Wildrose · 23 here")
        // Before the room is followed there's no count.
        #expect(RoomSummary.line(venue: "The Wildrose", lineupInChat: 1, friend: nil, count: nil)
            == "The Wildrose and 1 from tonight's lineup")
        #expect(RoomSummary.line(venue: "The Wildrose", lineupInChat: 0, friend: nil, count: nil) == nil)
        // A locale's room has no venue.
        #expect(RoomSummary.line(venue: nil, lineupInChat: 2, friend: "Jordan", count: 5) == nil)
    }

    @Test("An event's room shows its venue first; a locale's has none")
    func eventRoomPlace() {
        let venue = Venue(id: UUID(), name: "The Wildrose", photoURL: URL(string: "https://example.com/w.jpg"))
        let event = Event(id: UUID(), name: "Drag Bingo", startDate: .now, bannerURL: URL(string: "https://example.com/b.jpg"))

        let room = ChatRoom.event(event, at: venue)
        #expect(room.name == "Drag Bingo")
        #expect(room.place == HereNowPlace(name: "The Wildrose", photoURL: URL(string: "https://example.com/w.jpg")))
        #expect(room.venueID == venue.id)
        #expect(room.eventName == "Drag Bingo")

        #expect(ChatRoom.venue(venue).place?.name == "The Wildrose")
        // Rooms made without a venue name fall back to theirs.
        #expect(ChatRoom(kind: .venue, id: UUID(), name: "The Eagle").place?.name == "The Eagle")
        let locale = ChatRoom.locale(AppLocale(id: UUID(), name: "Seattle"))
        #expect(locale.place == nil)
        #expect(locale.venueID == nil)
    }
}

@Suite("Lineup presence in the room")
struct LineupPresenceFrameTests {
    @Test("The roster's lineup comes after the join, by person, lowercased")
    func rosterLineup() throws {
        let events = events("""
        { "__typename": "ChatJoined", "out_of_range": false,
          "roster": { "people": [], "friends": [],
            "lineup": [
              { "person_id": "4D9A0C21-8E76-4A5B-B3C2-6F1D8E0A9B33", "presence": "ONLINE" },
              { "person_id": "5e0b1d32-9f87-4b6c-84d3-7a2e9f1b0c44", "presence": "PUSH" },
              { "person_id": "6f1c2e43-0a98-4c7d-95e4-8b3f0a2c1d55", "presence": "OFFLINE" },
              { "person_id": null, "presence": "ONLINE" },
              { "person_id": "7a2d3f54-1b09-4d8e-a6f5-9c4a1b3d2e66", "presence": "SOMEWHERE" }
            ] },
          "history": [], "pinnedMessage": null }
        """)

        #expect(events.count == 5)
        guard case let .lineupPresence(presence) = try #require(events.last) else {
            Issue.record("Expected the lineup's presence")
            return
        }
        #expect(presence == [
            "4d9a0c21-8e76-4a5b-b3c2-6f1d8e0a9b33": .online,
            "5e0b1d32-9f87-4b6c-84d3-7a2e9f1b0c44": .push,
            "6f1c2e43-0a98-4c7d-95e4-8b3f0a2c1d55": .offline,
        ])
    }

    @Test("A roster without a lineup, from today's API, says nothing about it")
    func noRosterLineup() {
        let events = events(#"{ "__typename": "ChatJoined", "roster": { "people": [], "friends": [] }, "history": [] }"#)
        #expect(events.count == 4)
        #expect(!events.contains { if case .lineupPresence = $0 { true } else { false } })
    }

    @Test("ChatLineupChanged sends the whole list again")
    func lineupChanged() throws {
        let events = events("""
        { "__typename": "ChatLineupChanged",
          "lineup": [{ "person_id": "4d9a0c21-8e76-4a5b-b3c2-6f1d8e0a9b33", "presence": "PUSH" }] }
        """)
        guard case let .lineupPresence(presence) = try #require(events.first), events.count == 1 else {
            Issue.record("Expected the lineup's presence")
            return
        }
        #expect(presence == ["4d9a0c21-8e76-4a5b-b3c2-6f1d8e0a9b33": .push])
    }

    @Test("The subscription asks for lineup presence only once the API has it")
    func document() {
        let room = ChatRoom(kind: .venue, id: UUID(), name: "The Wildrose")
        let today = VenueChatConnection.subscriptionDocument(for: room)
        #expect(!today.contains("ChatLineupChanged"))
        #expect(!today.contains("lineup {"))

        let later = VenueChatConnection.subscriptionDocument(for: room, lineupPresence: true)
        #expect(later.contains("... on ChatLineupChanged { lineup { person_id: personId presence } }"))
        #expect(later.contains("recent_until: recentUntil }\n        lineup { person_id: personId presence }"))
    }

    @Test("The room keeps the lineup's presence until it changes")
    @MainActor
    func viewModel() {
        let viewModel = VenueChatViewModel(
            room: ChatRoom(kind: .venue, id: UUID(), name: "The Wildrose"),
            configuration: AppConfiguration(baseURL: URL(string: "https://api.hotmess.social")!),
            userID: UUID()
        )
        #expect(viewModel.lineupPresence == nil)
        viewModel.applyLineupPresence(["a": .online])
        #expect(viewModel.lineupPresence == ["a": .online])
        viewModel.applyLineupPresence([:])
        #expect(viewModel.lineupPresence == [:])
    }
}
