//
//  PrivateChat.swift
//  HotMess
//

import Foundation

/// A Ping's or Quickie pairing's chat (the API's `PrivateChat`): a
/// short-lived chat for a ping's circle, or a Quickie pair once both said yes.
/// What's said is kept only until it closes, then deleted on the server, and
/// the app keeps none of it either: lines live in memory while it's on screen.
struct PrivateChat: Decodable, Sendable, Equatable, Identifiable {
    /// `ping-<ping id>` or `quickie-<match id>`.
    let id: String
    /// When it closes at the latest; ending the ping or the pairing closes it sooner.
    let closesAt: Date?
    /// The newest lines, oldest first.
    let messages: [PrivateChatMessage]

    init(id: String, closesAt: Date?, messages: [PrivateChatMessage] = []) {
        self.id = id
        self.closesAt = closesAt
        self.messages = messages
    }

    /// Lenient: a line that doesn't decode is left out rather than losing the chat.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        closesAt = try container.decodeIfPresent(Date.self, forKey: .closesAt)
        messages = (try? container.decodeIfPresent([OptionalLine].self, forKey: .messages))?
            .compactMap(\.line) ?? []
    }

    private enum CodingKeys: String, CodingKey { case id, closesAt, messages }

    private struct OptionalLine: Decodable {
        let line: PrivateChatMessage?
        init(from decoder: any Decoder) throws { line = try? PrivateChatMessage(from: decoder) }
    }
}

/// A line in a `PrivateChat`. Its ID also names its chat, so it's reported on
/// its own (`ReportTarget.privateMessage`).
struct PrivateChatMessage: Decodable, Sendable, Equatable, Identifiable {
    struct Sender: Decodable, Sendable, Equatable {
        let id: UUID
        /// In full for friends, first name and last initial for anyone else.
        let name: String
    }

    let id: String
    let chatId: String
    let body: String
    let isMine: Bool
    /// Nil when they've deleted their account.
    let sender: Sender?
    let sentAt: Date
}

/// The words around Ping and Quickie chats, the same as Android's and the SDK's.
enum PrivateChatCopy {
    static let placeholder = String(localized: "Say something")
    static let pingTitle = String(localized: "Chat with your circle")
    static let quickieTitle = String(localized: "Chat to find each other")
    static let ephemeral = String(localized: "Messages disappear when the chat ends.")
    static let closed = String(localized: "This chat has ended.")
    static let pingWaiting = String(localized: "The chat opens once someone's in.")
    static let empty = String(localized: "No messages yet. Say hi.")
    static let bodyLimit = 1_000
}

extension PrivateChatMessage {
    /// A chat's lines as the screen shows them: in order, each once, whichever
    /// way it arrived (history, sending, the cable).
    static func merge(_ current: [PrivateChatMessage], _ incoming: [PrivateChatMessage]) -> [PrivateChatMessage] {
        guard !incoming.isEmpty else { return current }
        var byID: [String: PrivateChatMessage] = [:]
        for line in current + incoming { byID[line.id] = line }
        return byID.values.sorted { ($0.sentAt, $0.id) < ($1.sentAt, $1.id) }
    }
}

extension PairUpMatch {
    /// The API's `PrivateChats::AFTER_MEETING`.
    static let chatAfterMeeting: TimeInterval = 30 * 60

    /// Whether their chat may still be open after meeting.
    func chatsAfterMeeting(now: Date = .now) -> Bool {
        guard let metAt else { return false }
        return now < metAt.addingTimeInterval(Self.chatAfterMeeting)
    }
}

extension Ping {
    /// Whether the viewer can chat with its circle: they sent it or are in,
    /// and someone besides the sender is in.
    var canChat: Bool { (isMine || joined) && circle.count > 1 }
}

/// Which chat a push opens: a Ping's, or the Quickie at a venue.
enum PrivateChatLink: Hashable, Identifiable, Sendable {
    case ping(UUID)
    case quickie(venueID: UUID)

    var id: Self { self }
}
