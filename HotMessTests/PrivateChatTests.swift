//
//  PrivateChatTests.swift
//  HotMessTests
//

import AudienceKit
import Foundation
import Testing

@testable import HotMess

private let line = #"""
{ "id": "ping-p1.l1", "chatId": "ping-p1", "body": "On my way", "isMine": false,
  "sentAt": "2026-11-16T23:00:00.000Z", "sender": { "id": "8f1c1d2e-0000-4000-8000-000000000002", "name": "Ada L." } }
"""#

struct PrivateChatTests {
    @Test func readsLinesAndClosingsFromTheCable() {
        let message = AudienceCable.Event.result(Data(#"{ "data": { "privateChat": { "chatId": "ping-p1", "closed": false, "message": \#(line) } } }"#.utf8))
        guard case let .message(received)? = PrivateChatFrames.frames(from: message).first else {
            Issue.record("expected a line")
            return
        }
        #expect(received.body == "On my way")
        #expect(received.sender?.name == "Ada L.")

        let closed = AudienceCable.Event.result(Data(#"{ "data": { "privateChat": { "chatId": "ping-p1", "closed": true, "message": null } } }"#.utf8))
        #expect(PrivateChatFrames.frames(from: closed) == [.closed(chatID: "ping-p1")])

        #expect(PrivateChatFrames.frames(from: .result(Data(#"{ "data": null }"#.utf8))).isEmpty)
        #expect(PrivateChatFrames.frames(from: .result(Data(#"{ "data": null, "errors": [{ "message": "no" }] }"#.utf8))) == [.refused])
        #expect(PrivateChatFrames.frames(from: .subscribed) == [.connected])
    }

    @Test func decodesAChatLeniently() throws {
        let json = #"{ "id": "quickie-m1", "closesAt": "2026-11-17T05:00:00.000Z", "messages": [\#(line), { "id": "broken" }] }"#
        let chat = try JSONDecoder.hotMess.decode(PrivateChat.self, from: Data(json.utf8))
        #expect(chat.id == "quickie-m1")
        #expect(chat.messages.map(\.id) == ["ping-p1.l1"])
    }

    @Test func mergesLinesOnceInOrder() {
        func at(_ id: String, _ second: TimeInterval) -> PrivateChatMessage {
            PrivateChatMessage(id: id, chatId: "ping-p1", body: id, isMine: false, sender: nil,
                               sentAt: Date(timeIntervalSince1970: second))
        }
        let merged = PrivateChatMessage.merge([at("b", 2), at("a", 1)], [at("c", 3), at("b", 2)])
        #expect(merged.map(\.id) == ["a", "b", "c"])
    }

    @Test func aQuickieCanChatForHalfAnHourAfterMeeting() throws {
        let json = #"""
        { "id": "8f1c1d2e-0000-4000-8000-000000000003", "accepted": true, "partnerAccepted": true, "shared": false,
          "partnerShared": false, "bonus": false, "metAt": "2026-11-16T23:00:00.000Z", "endReason": null,
          "topic": { "key": "k", "text": "t" }, "partner": null }
        """#
        let match = try JSONDecoder.hotMess.decode(PairUpMatch.self, from: Data(json.utf8))
        let met = try #require(match.metAt)
        #expect(match.chatsAfterMeeting(now: met.addingTimeInterval(29 * 60)))
        #expect(!match.chatsAfterMeeting(now: met.addingTimeInterval(31 * 60)))
    }
}
