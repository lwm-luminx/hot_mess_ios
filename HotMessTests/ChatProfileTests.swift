//
//  ChatProfileTests.swift
//  HotMessTests
//

import Foundation
import Testing

@testable import HotMess

@Suite("Chat profile sheet")
struct ChatProfileTests {
    private func message(
        authorID: String = UUID().uuidString,
        isOwn: Bool = false,
        delivery: ChatDelivery = .sent,
        isFromPlace: Bool = false,
        isFromListing: Bool = false,
        isFromAudience: Bool = false
    ) -> ChatThreadMessage {
        ChatThreadMessage(
            id: UUID().uuidString, authorID: authorID, authorName: "Sam K.", avatarURL: nil,
            text: "hi", sentAt: .now, isOwn: isOwn, delivery: delivery,
            isFromPlace: isFromPlace, isFromListing: isFromListing, isFromAudience: isFromAudience
        )
    }

    @Test("Only people posting as themselves open a profile sheet")
    func opensProfile() {
        #expect(message().opensProfile)
        #expect(!message(isOwn: true).opensProfile)
        #expect(!message(delivery: .sending).opensProfile)
        #expect(!message(isFromPlace: true, isFromListing: true).opensProfile)
        #expect(!message(authorID: "person:\(UUID().uuidString)", isFromListing: true).opensProfile)
        #expect(!message(isFromListing: true, isFromAudience: true).opensProfile)
        #expect(!message(authorID: "audience:x").opensProfile)
    }

    @Test("Mutes are kept per room, on the device")
    func mutes() throws {
        let defaults = try #require(UserDefaults(suiteName: "ChatProfileTests.\(UUID().uuidString)"))
        let here = ChatRoom(kind: .venue, id: UUID(), name: "The Eagle")
        let elsewhere = ChatRoom(kind: .venue, id: UUID(), name: "Neighbours")
        let person = UUID()

        let mutes = ChatMutes(room: here, defaults: defaults)
        #expect(mutes.load().isEmpty)
        #expect(mutes.set(person, muted: true) == [person])
        #expect(ChatMutes(room: here, defaults: defaults).load() == [person])
        #expect(ChatMutes(room: elsewhere, defaults: defaults).load().isEmpty)
        #expect(mutes.set(person, muted: false).isEmpty)
        #expect(defaults.object(forKey: ChatMutes.key(for: here)) == nil)
    }

    @Test("Sends a friend request and reads where it stands")
    func friendRequest() throws {
        #expect(HotMessAPI.Documents.sendFriendRequest.contains("sendFriendRequest(input: { userId: $userId })"))

        let sent = Data(#"{ "sendFriendRequest": { "friendRequest": { "status": "PENDING" } } }"#.utf8)
        let response = try JSONDecoder.hotMess.decode(SendFriendRequestResponse.self, from: sent)
        #expect(response.sendFriendRequest.friendRequest.status == .pending)

        let accepted = Data(#"{ "sendFriendRequest": { "friendRequest": { "status": "ACCEPTED" } } }"#.utf8)
        #expect(try JSONDecoder.hotMess.decode(SendFriendRequestResponse.self, from: accepted)
            .sendFriendRequest.friendRequest.status == .accepted)
    }

    @Test("Answers carry the prompt they answer")
    func answerPromptID() {
        var answer = VenueMessage(body: "Jinkx", userID: UUID(), name: "Sam K.")
        answer.promptID = "p2"
        #expect(answer.threadMessage(currentUserID: nil).promptID == "p2")
    }
}
