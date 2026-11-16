//
//  PrivateChatLinkTests.swift
//  HotMessTests
//

import Foundation
import Testing

@testable import HotMess

@Suite("Private chat links")
struct PrivateChatLinkTests {
    private let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    @Test("A Ping chat push opens the chat, and the Ping link still opens the Ping")
    func pingChat() {
        #expect(DeepLink.destination(for: URL(string: "https://hotmess.social/pings/\(id.uuidString)/chat")) == .pingChat(id))
        #expect(DeepLink.destination(for: URL(string: "hotmess://pings/\(id.uuidString)/chat")) == .pingChat(id))
        #expect(DeepLink.destination(for: URL(string: "https://hotmess.social/pings/\(id.uuidString)")) == .route(.ping(id, invitation: nil)))
    }

    @Test("A Quickie chat push opens the chat, and the venue link still opens the venue")
    func quickieChat() {
        #expect(DeepLink.destination(for: URL(string: "https://hotmess.social/venues/\(id.uuidString)/quickie")) == .quickieChat(id))
        #expect(DeepLink.destination(for: URL(string: "https://hotmess.social/venues/\(id.uuidString)/quickie/x")) != .quickieChat(id))
        #expect(DeepLink.destination(for: URL(string: "https://hotmess.social/venues/\(id.uuidString)")) == .route(.venue(id)))
        #expect(DeepLink.destination(for: URL(string: "https://hotmess.social/venues/\(id.uuidString)/chat")) == .venueChat(id))
    }
}
