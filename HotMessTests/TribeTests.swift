//
//  TribeTests.swift
//  HotMessTests
//

import AudienceKit
import Foundation
import Testing

@testable import HotMess

private let me = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
private let jordan = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
private let sam = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

private let bears = #"{ "id": "t1", "name": "Bear", "both_phrase": "You're both bears" }"#
private let games = #"{ "id": "t2", "name": "Board games", "both_phrase": "You both play board games" }"#

private func events(_ room: String) -> [VenueChatConnection.Event] {
    VenueChatConnection.events(from: .result(Data(#"{ "data": { "room": \#(room) } }"#.utf8)))
}

@Suite("Tribes")
struct TribeTests {
    @Test("The BothLine is the first phrase plus a count of the rest")
    func bothLine() {
        let tribes = [
            SharedTribe(id: "t1", name: "Bear", bothPhrase: "You're both bears"),
            SharedTribe(id: "t2", name: "Board games", bothPhrase: "You both play board games"),
        ]
        #expect([SharedTribe]().bothLine == nil)
        #expect(Array(tribes.prefix(1)).bothLine == "You're both bears")
        #expect(tribes.bothLine == "You're both bears +1")
    }

    @Test("The room asks for shared tribes only when told to")
    func subscriptionDocument() {
        let room = ChatRoom(kind: .venue, id: UUID(), name: "The Eagle")
        #expect(!VenueChatConnection.subscriptionDocument(for: room).contains("sharedTribes"))
        let document = VenueChatConnection.subscriptionDocument(for: room, sharedTribes: true)
        #expect(document.contains("people { user_id: userId name avatar_url: avatarUrl friend shared_tribes: sharedTribes"))
        #expect(document.contains("fragment Line on ChatMessage {"))
        #expect(document.components(separatedBy: "shared_tribes: sharedTribes").count == 5)
    }

    @Test("Joining reads shared tribes off the roster, and a line carries its sender's")
    func roomEvents() throws {
        let joined = events("""
        { "__typename": "ChatJoined", "out_of_range": false,
          "roster": { "people": [
              { "user_id": "\(jordan)", "name": "Jordan P.", "friend": false, "shared_tribes": [\(bears), \(games)] },
              { "user_id": "\(sam)", "name": "Sam K.", "friend": false, "shared_tribes": [] } ],
            "friends": [], "recent": [] },
          "history": [], "pinnedMessage": null }
        """)
        guard case let .sharedTribes(tribes) = try #require(joined.last) else {
            Issue.record("Expected shared tribes after the roster")
            return
        }
        #expect(tribes[jordan]?.map(\.name) == ["Bear", "Board games"])
        #expect(tribes[sam] == [])

        let posted = events("""
        { "__typename": "ChatMessagePosted", "sender_presence": null,
          "message": { "id": "\(UUID())", "message": "hi", "user_id": "\(jordan)", "kind": "TEXT", "pinned": false,
            "posted_as_venue": false, "shared_tribes": [\(bears)] } }
        """)
        guard case let .received(message) = try #require(posted.first) else {
            Issue.record("Expected the line")
            return
        }
        #expect(message.sharedTribes?.map(\.bothPhrase) == ["You're both bears"])
    }

    @Test("An older room without tribes says nothing about them")
    func olderRoom() throws {
        let joined = events("""
        { "__typename": "ChatJoined", "out_of_range": false,
          "roster": { "people": [{ "user_id": "\(jordan)", "name": "Jordan P.", "friend": false }],
            "friends": [], "recent": [] },
          "history": [], "pinnedMessage": null }
        """)
        #expect(!joined.contains { if case .sharedTribes = $0 { true } else { false } })
    }

    @Test("An arrival brings their shared tribes; the viewer shares none with themself")
    @MainActor
    func viewModel() {
        let viewModel = VenueChatViewModel(
            room: ChatRoom(kind: .venue, id: UUID(), name: "The Eagle"),
            configuration: AppConfiguration(baseURL: URL(string: "https://api.hotmess.social")!),
            userID: me
        )
        var line = VenueMessage(body: "hi", userID: jordan, name: "Jordan P.")
        line.sharedTribes = [SharedTribe(id: "t1", name: "Bear", bothPhrase: "You're both bears")]
        viewModel.receive(line)
        var own = VenueMessage(body: "hey", userID: me)
        own.sharedTribes = [SharedTribe(id: "t1", name: "Bear", bothPhrase: "You're both bears")]
        viewModel.receive(own)

        #expect(viewModel.sharedTribes(with: jordan).map(\.name) == ["Bear"])
        #expect(viewModel.sharedTribes(with: me).isEmpty)
        #expect(viewModel.sharedTribes(with: sam).isEmpty)
    }

    @Test("The picker holds picks to the cap and finds tribes by name")
    func choices() {
        let choices = TribeChoices(
            categories: [
                TribeCategory(key: "scene", name: "Body type and scene", tribes: [Tribe(id: "t1", name: "Bear")]),
                TribeCategory(key: "games", name: "Games and play", tribes: [Tribe(id: "t2", name: "Board games")]),
            ],
            cap: 1,
            picked: ["t2"]
        )
        #expect(choices.isAtCap)
        #expect(choices.pickedTribes.map(\.name) == ["Board games"])
        #expect(choices.matching("bo").map(\.tribe.name) == ["Board games"])
        #expect(choices.matching("  ").isEmpty)
    }

    @Test("Tags and tribes show lowercase, with dashes for spaces")
    func tagLabel() {
        #expect(Tribe(id: "t1", name: "Board games").label == "board-games")
        #expect("  Resident   DJ ".tagLabel == "resident-dj")
        #expect("Bear".tagLabel == "bear")
    }
}
