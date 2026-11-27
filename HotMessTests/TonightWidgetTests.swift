//
//  TonightWidgetTests.swift
//  HotMessTests
//

import Foundation
import Testing

@testable import HotMess

@MainActor
struct TonightWidgetTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func friend(_ name: String) -> Friend {
        Friend(id: UUID(), name: name)
    }

    private func ping(
        _ id: String, by name: String = "Sam Rivera", at offset: TimeInterval = 0, mine: Bool = false,
        joined: Bool = false, via: Friend? = nil, joins: [String] = []
    ) -> Ping {
        Ping(
            id: id, user: friend(name), createdAt: base + offset, expiresAt: base + 3600, isMine: mine, joined: joined,
            joins: joins.enumerated().map { PingJoin(id: "\(id)-\($0.offset)", user: friend($0.element)) }, via: via
        )
    }

    // MARK: - Ping Live Activity

    @Test("The Live Activity shows your Ping, else one you're in, else the newest a friend sent")
    func pingChoice() {
        let older = ping("older", at: 0)
        let newer = ping("newer", at: 60)
        let joined = ping("joined", at: 30, joined: true)
        let mine = ping("mine", mine: true)
        #expect(LiveActivities.shown(myPing: mine, friendPings: [newer, joined], now: base)?.id == "mine")
        #expect(LiveActivities.shown(myPing: nil, friendPings: [newer, joined], now: base)?.id == "joined")
        #expect(LiveActivities.shown(myPing: nil, friendPings: [older, newer], now: base)?.id == "newer")
        #expect(LiveActivities.shown(myPing: nil, friendPings: [older], now: base + 7200) == nil)
    }

    @Test("A Ping seen only through someone in its circle isn't offered to join")
    func pingThroughCircleNotOffered() {
        let through = ping("through", via: friend("Alex Kim"))
        #expect(LiveActivities.shown(myPing: nil, friendPings: [through], now: base) == nil)
    }

    @Test("A friend's Ping offers I'm in; one you're in offers Chat")
    func pingButtons() {
        #expect(LiveActivities.state(for: ping("a")).actions == [.joinPing])
        #expect(LiveActivities.state(for: ping("a", joined: true)).actions == [.chat])
        #expect(LiveActivities.state(for: ping("a", mine: true)).actions == [.chat])
        #expect(LiveActivities.state(for: ping("a")).chatURL?.absoluteString == "hotmess://pings/a/chat")
    }

    // MARK: - Quickie Live Activity

    private func quickie(_ status: PairUpStatus) -> PairUpState {
        PairUpState(status: status, lookFor: nil, metCount: 0, match: nil, bonus: nil)
    }

    @Test("A Quickie offers I'm in and New topic while proposed, New topic while waiting, Chat once revealed")
    func quickieButtons() {
        #expect(LiveActivities.actions(for: quickie(.proposed)) == [.acceptQuickie, .newTopic])
        #expect(LiveActivities.actions(for: quickie(.waiting)) == [.newTopic])
        #expect(LiveActivities.actions(for: quickie(.revealed)) == [.chat])
        #expect(LiveActivities.actions(for: quickie(.searching)).isEmpty)
    }

    // MARK: - Tonight widget

    @Test("The widget keeps your Ping and friends' Pings, joined first, never ones seen through a circle")
    func widgetPings() {
        let pings = TonightWidget.pings(
            myPing: ping("mine", mine: true),
            friendPings: [ping("old", at: 0), ping("new", at: 60), ping("in", at: 10, joined: true),
                          ping("through", via: friend("Alex Kim"))],
            at: base
        )
        #expect(pings.map(\.id) == ["mine", "in", "new", "old"])
        #expect(pings.first?.sender == String(localized: "You"))
        #expect(pings.last?.sender == "Sam")
    }

    @Test("Who's in reads as first names, two then a count")
    func peopleLine() {
        let entry = TonightWidget.entry(for: ping("a", joins: ["Alex Kim", "Jo P.", "Kai Lee", "Max R."]))
        #expect(entry.people == ["Alex", "Jo", "Kai", "Max"])
        #expect(entry.peopleLine == "Alex, Jo +2")
        #expect(TonightWidget.entry(for: ping("b")).peopleLine == nil)
        #expect(entry.canJoin)
    }

    @Test("Ended Pings and events drop off, and the next change is the next end")
    func snapshotAgesOut() {
        let snapshot = TonightSnapshot(
            updatedAt: base, events: [
                .init(id: "e1", name: "Bingo", startsAt: base, endsAt: base + 600),
                .init(id: "e2", name: "Disco", startsAt: base + 1200, endsAt: nil),
            ],
            pings: [TonightWidget.entry(for: ping("p"))]
        )
        #expect(snapshot.nextChange(after: base) == base + 600)
        #expect(snapshot.current(at: base + 900).events.map(\.id) == ["e2"])
        #expect(snapshot.current(at: base + 4000).pings.isEmpty)
        #expect(snapshot.current(at: base + 1200 + 5 * 3600).events.isEmpty)
    }

    // MARK: - Rotating events

    private func venue(_ name: String, address: String?, id: UUID = UUID()) -> Venue {
        Venue(id: id, name: name, address: address)
    }

    private func event(_ name: String, in hours: Double, at venue: Venue? = nil, rsvp: RSVP = .unsure) -> HotMess.Event {
        var event = HotMess.Event(id: UUID(), name: name, startDate: base + hours * 3600, venue: venue)
        event.rsvp = rsvp
        return event
    }

    @Test("An event's location is its venue and street, the address up to its first comma")
    func eventLocation() {
        let purr = TonightWidget.entry(for: event("Bingo", in: 1, at: venue("Purr", address: "1518 11th Ave, Seattle, WA")))
        #expect(purr.location == "Purr · 1518 11th Ave")
        #expect(TonightWidget.entry(for: event("Bingo", in: 1, at: venue("Purr", address: nil))).location == "Purr")
        #expect(TonightWidget.entry(for: event("Bingo", in: 1, at: venue("Purr", address: ""))).location == "Purr")
        #expect(TonightWidget.entry(for: event("Bingo", in: 1)).location == nil)
    }

    @Test("Going comes from the user's RSVP")
    func eventGoing() {
        #expect(TonightWidget.entry(for: event("A", in: 1, rsvp: .attending)).isGoing)
        #expect(!TonightWidget.entry(for: event("A", in: 1, rsvp: .maybe)).isGoing)
    }

    @Test("Upcoming keeps the event you're at first, then the next week's soonest first, at most the limit")
    func upcomingEvents() {
        let at = event("Here", in: -1)
        let later = event("Later", in: 30)
        let soon = event("Soon", in: 2)
        let nextMonth = event("Next month", in: 24 * 30)
        let over = HotMess.Event(id: UUID(), name: "Over", startDate: base - 7200, endDate: base - 60)
        let names = TonightWidget.upcoming([later, soon, at, nextMonth, over], leading: at, myPing: nil, at: base)
            .map(\.name)
        #expect(names == ["Here", "Soon", "Later"])
        let many = (1...(TonightWidget.limit + 3)).map { event("E\($0)", in: Double($0)) }
        #expect(TonightWidget.upcoming(many, myPing: nil, at: base).count == TonightWidget.limit)
    }

    @Test("Events your own Ping names are marked pinged")
    func upcomingPinged() {
        let bingo = event("Bingo", in: 1)
        let mine = Ping(
            id: "mine", user: friend("Me Too"), createdAt: base, expiresAt: base + 3600 * 8, isMine: true,
            targets: [PingTarget(id: "t", event: bingo)]
        )
        let entries = TonightWidget.upcoming([bingo, event("Disco", in: 2)], myPing: mine, at: base)
        #expect(entries.map(\.isPinged) == [true, false])
    }

    @Test("Ping on an event adds it to your Ping's picks once, or starts a Ping with just it")
    func pingPlaces() {
        let id = UUID()
        let venueID = UUID()
        #expect(TonightWidget.pingPlaces(adding: id, to: nil) == [.event(id)])
        let mine = Ping(
            id: "mine", user: friend("Me Too"), createdAt: base, expiresAt: base + 3600, isMine: true,
            targets: [PingTarget(id: "t", venue: venue("Purr", address: nil, id: venueID))]
        )
        #expect(TonightWidget.pingPlaces(adding: id, to: mine) == [.venue(venueID), .event(id)])
        let already = Ping(
            id: "mine", user: friend("Me Too"), createdAt: base, expiresAt: base + 3600, isMine: true,
            targets: [PingTarget(id: "t", event: HotMess.Event(id: id, name: "Bingo", startDate: base))]
        )
        #expect(TonightWidget.pingPlaces(adding: id, to: already) == [.event(id)])
    }

    @Test("Only events tonight offer Ping")
    func pingable() {
        let tonight = TonightSnapshot.Event(id: "a", name: "A", startsAt: base + 3 * 3600)
        let tomorrow = TonightSnapshot.Event(id: "b", name: "B", startsAt: base + 30 * 3600)
        #expect(tonight.isPingable(at: base))
        #expect(!tomorrow.isPingable(at: base))
    }

    @Test("The featured event moves on every rotation and wraps around")
    func rotation() {
        let start = Date(timeIntervalSince1970: (base.timeIntervalSince1970 / TonightSnapshot.rotation).rounded(.down)
            * TonightSnapshot.rotation)
        let snapshot = TonightSnapshot(
            updatedAt: start,
            events: ["a", "b", "c"].map { TonightSnapshot.Event(id: $0, name: $0, startsAt: start + 3600) },
            pings: []
        )
        let first = snapshot.featuredEvent(at: start)?.id
        let ids = (0..<4).compactMap { snapshot.featuredEvent(at: start + Double($0) * TonightSnapshot.rotation)?.id }
        #expect(Set(ids.prefix(3)) == ["a", "b", "c"])
        #expect(ids[3] == first)
        // Within one slot it stays put, so a redraw after a button keeps it.
        #expect(snapshot.featuredEvent(at: start + TonightSnapshot.rotation - 1)?.id == first)
        #expect(TonightSnapshot.nextRotation(after: start + 1) == start + TonightSnapshot.rotation)
        #expect(TonightSnapshot.empty.featuredEvent(at: start) == nil)
    }

    @Test("The card features tonight's events, else the next one, never one days away")
    func featuredPrefersTonight() {
        let start = Date(timeIntervalSince1970: (base.timeIntervalSince1970 / TonightSnapshot.rotation).rounded(.down)
            * TonightSnapshot.rotation)
        let friday = TonightSnapshot.Event(id: "fri", name: "Hyper Pop", startsAt: start + 27 * 3600)
        let saturday = TonightSnapshot.Event(id: "sat", name: "No Theme", startsAt: start + 51 * 3600)
        let sunday = TonightSnapshot.Event(id: "sun", name: "Karaoke", startsAt: start + 75 * 3600)
        let nothingTonight = TonightSnapshot(updatedAt: start, events: [friday, saturday, sunday], pings: [])
        let featured = (0..<6).compactMap {
            nothingTonight.featuredEvent(at: start + Double($0) * TonightSnapshot.rotation)?.id
        }
        #expect(Set(featured) == ["fri"])
        #expect(!nothingTonight.rotates(at: start))

        let bingo = TonightSnapshot.Event(id: "bingo", name: "Bingo", startsAt: start + 2 * 3600)
        let karaoke = TonightSnapshot.Event(id: "karaoke", name: "Karaoke", startsAt: start + 3 * 3600)
        let twoTonight = TonightSnapshot(updatedAt: start, events: [bingo, karaoke, friday, sunday], pings: [])
        let rotating = (0..<4).compactMap {
            twoTonight.featuredEvent(at: start + Double($0) * TonightSnapshot.rotation)?.id
        }
        #expect(Set(rotating) == ["bingo", "karaoke"])
        #expect(twoTonight.rotates(at: start))
        #expect(twoTonight.featuredEvents(at: start).map(\.id) == ["bingo", "karaoke"])
    }

    @Test("Previous and next step through every event, wrapping, and hold until the browse ends")
    func stepping() {
        let events = ["a", "b", "c"].map { TonightSnapshot.Event(id: $0, name: $0, startsAt: base + 30 * 3600) }
        let snapshot = TonightSnapshot(updatedAt: base, events: events, pings: [])
        #expect(snapshot.event(1, from: events[0], at: base)?.id == "b")
        #expect(snapshot.event(-1, from: events[0], at: base)?.id == "c")
        #expect(snapshot.event(1, from: events[2], at: base)?.id == "a")
        let browsing = TonightBrowse(eventID: "c", until: base + 600)
        #expect(snapshot.featuredEvent(at: base, browsing: browsing)?.id == "c")
        #expect(snapshot.featuredEvent(at: base + 601, browsing: browsing)?.id == snapshot.featuredEvent(at: base + 601)?.id)
        let gone = TonightBrowse(eventID: "zzz", until: base + 600)
        #expect(snapshot.featuredEvent(at: base, browsing: gone)?.id == snapshot.featuredEvent(at: base)?.id)
    }

    @Test("At a venue, the widget lists the rest of the city's events too, soonest first")
    func nowMergesCityEvents() throws {
        let suntrapp = venue("The SunTrapp", address: nil)
        let milk = venue("Milk+", address: nil)
        let sunday = event("Sunday Karaoke", in: 75, at: suntrapp)
        let therapy = event("Therapy Thursdays", in: 2, at: milk)
        let now = Now(title: "The SunTrapp", venue: suntrapp, events: [sunday], cityEvents: [therapy, sunday])
        let names = TonightWidget.upcoming(now.events + now.cityEvents, leading: now.event, myPing: nil, at: base)
            .map(\.name)
        #expect(names == ["Therapy Thursdays", "Sunday Karaoke"])
    }

    @Test("A snapshot saved before location and buttons still reads")
    func oldSnapshotDecodes() throws {
        let json = #"""
        {"updatedAt":"2026-11-20T00:00:00Z","localeName":"Seattle","events":[{"id":"e","name":"Bingo",
        "place":"Purr","startsAt":"2026-11-20T03:00:00Z"}],"pings":[]}
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(TonightSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.events.first?.location == "Purr")
        #expect(snapshot.events.first?.isGoing == false)
        #expect(snapshot.localeID == nil)
    }

    @Test("A button's change lands on its event only")
    func updatingEvent() {
        let snapshot = TonightSnapshot(
            updatedAt: base,
            events: [.init(id: "a", name: "A", startsAt: base), .init(id: "b", name: "B", startsAt: base)],
            pings: []
        )
        let changed = snapshot.updating(event: "b") { $0.going = true }
        #expect(changed.events.map(\.isGoing) == [false, true])
    }
}
