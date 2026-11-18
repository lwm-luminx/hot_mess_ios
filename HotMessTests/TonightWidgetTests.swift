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
}
