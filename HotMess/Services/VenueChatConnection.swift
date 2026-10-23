//
//  VenueChatConnection.swift
//  HotMess
//

import AudienceKit
import Foundation
import os

/// One chat room's subscription on the app's cable: a venue's room, or a
/// locale's (see `ChatRoom`).
///
/// Realtime on the API is GraphQL subscriptions carried over the app's one
/// Action Cable connection (`AppModel.cable`). The room's `venueChat` /
/// `localeChat` subscription runs there beside every other one, and every
/// result it sends is one `ChatRoomEvent`, which this turns into the room's
/// `Event`s.
///
/// A venue's room is only open to people at the venue, and a locale's to people
/// out in the locale away from its venues: the server refuses the subscription
/// otherwise (an error and no data), and ends it with `ChatLeft` when someone's
/// presence lapses. Either way the room reports `.notPresent` instead of
/// retrying. Admins can join from anywhere; `ChatJoined` says whether they're
/// out of range, and `ChatRangeChanged` whenever that changes.
///
/// Lines are sent with the `sendMyChatMessage` mutation (see `HotMessAPI`),
/// not over the cable; they come back here as `ChatMessagePosted` like
/// everyone else's.
enum VenueChatConnection {
    enum Event: Sendable {
        /// The room was joined (its `ChatJoined` arrived); lines can be sent.
        case connected
        case received(VenueMessage)
        /// The server turned the subscription away, or ended it, because the
        /// user isn't in the room's place (by the last position they reported),
        /// or was banned or removed from it.
        case notPresent
        /// Whether the user is outside the room's place. Only admins are let in
        /// from outside, so `true` means they're there because they're an admin.
        case range(outOfRange: Bool)
        /// Everyone in the room now, the user included, sent on joining.
        /// `people` names them, and `friends` is every one of the user's
        /// friends, by full name, in the room or not. `recent` is who left in
        /// the last 30 minutes, latest to leave first, whom the room still
        /// lists, offline; they aren't in `people`.
        case roster(online: Set<UUID>, people: [RoomPerson], friends: [Friend], recent: [RecentRoomPerson])
        /// Someone's first socket joined the room (`true`) or their last one
        /// left. A join carries their name and avatar when the server sends them.
        case presence(userID: UUID, online: Bool, name: String?, avatarURL: URL?)
        /// Someone left the room (or was never in it) but a notification still
        /// reaches them: the server only says so about the user's friends, and
        /// to admins. Drawn as a yellow dot.
        case reachable(userID: UUID)
        /// Someone's last connection left, and the room keeps listing them
        /// until `until`, offline, or reachable by push (`.push`) for the
        /// user's friends and admins. Sent instead of `presence` or
        /// `reachable` by servers that keep people who were just here.
        case recent(userID: UUID, presence: PresenceState, until: Date)
        /// The room's recent messages, oldest first, and the announcement
        /// pinned under its title (however old), sent on joining, and when the
        /// room stops showing messages to everyone but its admins (`nil` from
        /// an API that doesn't say).
        case history(messages: [VenueMessage], pinned: VenueMessage?, expiresBefore: Date?)
        /// An announcement was pinned (with it), or unpinned (`nil`).
        case pin(id: UUID, announcement: VenueMessage?)
        /// An admin removed a message; nobody sees it again.
        case removed(id: UUID)
        /// An admin cleared the room, or (`expired`) its oldest messages
        /// expired: every message sent up to `at` is gone (all of them when
        /// `at` is unreadable).
        case cleared(at: Date?, expired: Bool)
        /// The socket dropped or went quiet. The cable rejoins the room on its
        /// own (a fresh `ChatJoined`) unless `reconnects` is false: the
        /// session ended.
        case disconnected(String?, reconnects: Bool)
    }

    static let operationName = "ChatRoom"

    /// The room's subscription, aliased to `room` whichever field it is, with
    /// its fields aliased to the keys the app's models decode. A watcher
    /// (`watch`) follows the room without being in it: the server records no
    /// presence, so nobody sees them as in chat.
    static func subscriptionDocument(for room: ChatRoom, watch: Bool = false) -> String {
        let line = HotMessAPI.Documents.roomMessageFields
        let watching = watch ? ", watch: true" : ""
        return """
        subscription ChatRoom($id: ID!) {
          room: \(room.channelName)(\(room.subscriptionKey): $id\(watching)) {
            __typename
            ... on ChatJoined {
              out_of_range: outOfRange
              roster {
                people { user_id: userId name avatar_url: avatarUrl friend }
                friends { user_id: userId name }
                recent { user_id: userId name avatar_url: avatarUrl friend presence last_seen_at: lastSeenAt recent_until: recentUntil }
              }
              history { ...Posted }
              pinnedMessage { ...Posted }
              expires_before: expiresBefore
            }
            ... on ChatMessagePosted { ...Posted }
            ... on ChatMessageUpdated { message { ...Line } }
            ... on ChatMessageRemoved { message_id: messageId }
            ... on ChatPinChanged { message_id: messageId is_pinned: pinned announcement { ...Line } }
            ... on ChatRoomCleared { cleared_at: clearedAt expired }
            ... on ChatPresenceChanged { user_id: userId presence name avatar_url: avatarUrl recent_until: recentUntil }
            ... on ChatRangeChanged { out_of_range: outOfRange }
            ... on ChatLeft { reason }
          }
        }
        fragment Posted on ChatMessagePosted { sender_presence: senderPresence message { ...Line } }
        fragment Line on ChatMessage { \(line) }
        """
    }

    /// The subscription's variables: the room's ID.
    static func variables(for room: ChatRoom) -> [String: GraphQLValue] {
        ["id": .string(room.id.uuidString.lowercased())]
    }

    /// The room's operation on the cable.
    static func subscribe(to room: ChatRoom, on cable: AudienceCable, audienceID: String, watch: Bool = false) async
        -> AsyncStream<AudienceCable.Event> {
        await cable.subscribe(
            query: subscriptionDocument(for: room, watch: watch),
            variables: variables(for: room),
            operationName: operationName,
            audienceID: audienceID
        )
    }

    /// The events one of the cable's events means to the room.
    static func events(from event: AudienceCable.Event) -> [Event] {
        switch event {
        case .subscribed:
            // The room says it's joined with `ChatJoined`, its first result.
            []
        case let .result(data):
            events(fromResult: data)
        case .rejected:
            // Another audience's token, or someone the audience banned.
            [.notPresent]
        case let .disconnected(reason, reconnects):
            [.disconnected(reason, reconnects: reconnects)]
        }
    }

    /// What one `{ data, errors }` result means. A result with errors and no
    /// event is the server refusing the subscription (not at the venue,
    /// banned); one for an event this build doesn't know means nothing.
    static func events(fromResult data: Data) -> [Event] {
        guard let result = try? JSONDecoder().decode(GraphQLResult.self, from: data) else { return [] }
        if let room = result.room {
            return room.events
        }
        if result.hasErrors {
            Log.realtime.error("Chat subscription refused: \(result.errorSummary, privacy: .public)")
            return [.notPresent]
        }
        return []
    }

    // MARK: - Wire format

    private typealias Lenient<Value: Decodable> = GraphQLCable.Lenient<Value>

    /// `{ data: { room }, errors }`.
    private struct GraphQLResult: Decodable {
        let room: RoomEvent?
        let errors: [String]

        var hasErrors: Bool { !errors.isEmpty }
        var errorSummary: String { errors.joined(separator: "; ") }

        enum CodingKeys: String, CodingKey { case data, errors }
        private enum DataKeys: String, CodingKey { case room }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let data = try? container.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
            room = (try? data?.decodeIfPresent(RoomEvent.self, forKey: .room)) ?? nil
            errors = GraphQLCable.errors(in: container, forKey: .errors)
        }
    }

    /// One `ChatRoomEvent`, by its `__typename`, as the events it means.
    private struct RoomEvent: Decodable {
        let events: [Event]

        enum CodingKeys: String, CodingKey {
            case typename = "__typename"
            case outOfRange = "out_of_range"
            case roster, history, pinnedMessage, message, announcement, presence, name, reason
            case isPinned = "is_pinned"
            case messageID = "message_id"
            case clearedAt = "cleared_at"
            case expiresBefore = "expires_before"
            case expired
            case userID = "user_id"
            case avatarURL = "avatar_url"
            case recentUntil = "recent_until"
        }

        private enum RosterKeys: String, CodingKey { case people, friends, recent }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let typename = (try? container.decodeIfPresent(String.self, forKey: .typename)) ?? nil

            switch typename {
            case "ChatJoined":
                let roster = try? container.nestedContainer(keyedBy: RosterKeys.self, forKey: .roster)
                // Each person, friend and line on its own, so one bad entry drops only itself.
                let people = ((try? roster?.decodeIfPresent([Lenient<PersonWire>].self, forKey: .people)) ?? nil)?
                    .compactMap { $0.value?.person } ?? []
                let friends = ((try? roster?.decodeIfPresent([Lenient<FriendWire>].self, forKey: .friends)) ?? nil)?
                    .compactMap { $0.value?.friend } ?? []
                let recent = ((try? roster?.decodeIfPresent([Lenient<RecentWire>].self, forKey: .recent)) ?? nil)?
                    .compactMap { $0.value?.person } ?? []
                let history = ((try? container.decodeIfPresent([Lenient<Posted>].self, forKey: .history)) ?? nil)?
                    .compactMap { $0.value?.message } ?? []
                let pinned = ((try? container.decodeIfPresent(Posted.self, forKey: .pinnedMessage)) ?? nil)?.message
                let outOfRange = ((try? container.decodeIfPresent(Bool.self, forKey: .outOfRange)) ?? nil) ?? false
                let expiresBefore = ((try? container.decodeIfPresent(String.self, forKey: .expiresBefore)) ?? nil)
                    .flatMap(HotMessDecoding.date(from:))

                events = [
                    .connected,
                    .range(outOfRange: outOfRange),
                    .roster(online: Set(people.map(\.id)), people: people, friends: friends, recent: recent),
                    .history(messages: history, pinned: pinned, expiresBefore: expiresBefore),
                ]
            case "ChatMessagePosted":
                events = (try? Posted(from: decoder).message).map { [.received($0)] } ?? []
            case "ChatMessageUpdated":
                events = Self.message(in: container, forKey: .message).map { [.received($0)] } ?? []
            case "ChatMessageRemoved":
                events = Self.id(in: container, forKey: .messageID).map { [.removed(id: $0)] } ?? []
            case "ChatPinChanged":
                guard let id = Self.id(in: container, forKey: .messageID) else {
                    events = []
                    return
                }
                let isPinned = ((try? container.decodeIfPresent(Bool.self, forKey: .isPinned)) ?? nil) ?? false
                let announcement = isPinned ? Self.message(in: container, forKey: .announcement) : nil
                events = [.pin(id: id, announcement: announcement)]
            case "ChatRoomCleared":
                let at = ((try? container.decodeIfPresent(String.self, forKey: .clearedAt)) ?? nil)
                    .flatMap(HotMessDecoding.date(from:))
                let expired = ((try? container.decodeIfPresent(Bool.self, forKey: .expired)) ?? nil) ?? false
                events = [.cleared(at: at, expired: expired)]
            case "ChatPresenceChanged":
                guard let userID = Self.id(in: container, forKey: .userID),
                      let presence = ((try? container.decodeIfPresent(String.self, forKey: .presence)) ?? nil)?.uppercased()
                else {
                    events = []
                    return
                }
                let recentUntil = ((try? container.decodeIfPresent(String.self, forKey: .recentUntil)) ?? nil)
                    .flatMap(HotMessDecoding.date(from:))
                if presence != "ONLINE", let recentUntil {
                    events = [.recent(userID: userID, presence: presence == "PUSH" ? .push : .offline, until: recentUntil)]
                } else if presence == "PUSH" {
                    events = [.reachable(userID: userID)]
                } else {
                    events = [.presence(
                        userID: userID,
                        online: presence == "ONLINE",
                        name: ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil)?.nonBlank,
                        avatarURL: ((try? container.decodeIfPresent(String.self, forKey: .avatarURL)) ?? nil)?.nonBlankURL
                    )]
                }
            case "ChatRangeChanged":
                let outOfRange = ((try? container.decodeIfPresent(Bool.self, forKey: .outOfRange)) ?? nil) ?? false
                let expiresBefore = ((try? container.decodeIfPresent(String.self, forKey: .expiresBefore)) ?? nil)
                    .flatMap(HotMessDecoding.date(from:))
                events = [.range(outOfRange: outOfRange)]
            case "ChatLeft":
                // AWAY, BANNED or REMOVED: out of the room either way.
                events = [.notPresent]
            default:
                events = []
            }
        }

        private static func id(in container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> UUID? {
            ((try? container.decodeIfPresent(String.self, forKey: key)) ?? nil).flatMap(UUID.init(uuidString:))
        }

        private static func message(in container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> VenueMessage? {
            ((try? container.decodeIfPresent(VenueMessage.Payload.self, forKey: key)) ?? nil)
                .map(VenueMessage.init(payload:))
        }
    }

    /// A `ChatMessagePosted`: the line, with its sender's presence in the
    /// room (`ONLINE`, `PUSH`, or null) as the line's `presence`.
    private struct Posted: Decodable {
        let message: VenueMessage?

        enum CodingKeys: String, CodingKey {
            case message
            case senderPresence = "sender_presence"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            var message = ((try? container.decodeIfPresent(VenueMessage.Payload.self, forKey: .message)) ?? nil)
                .map(VenueMessage.init(payload:))
            message?.presence = ((try? container.decodeIfPresent(String.self, forKey: .senderPresence)) ?? nil)
                .flatMap { PresenceState(wire: $0) }
            self.message = message
        }
    }

    /// One of the roster's `people`.
    private struct PersonWire: Decodable {
        let person: RoomPerson?

        enum CodingKeys: String, CodingKey {
            case name, friend
            case userID = "user_id"
            case avatarURL = "avatar_url"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let id = try? container.decodeIfPresent(UUID.self, forKey: .userID) else {
                person = nil
                return
            }
            person = RoomPerson(
                id: id,
                name: (try? container.decodeIfPresent(String.self, forKey: .name)).flatMap({ $0.nonBlank }),
                avatarURL: (try? container.decodeIfPresent(String.self, forKey: .avatarURL)).flatMap({ $0.nonBlankURL }),
                isFriend: (try? container.decodeIfPresent(Bool.self, forKey: .friend)) ?? false
            )
        }
    }

    /// One of the roster's `recent`: someone who left lately, and until when
    /// the room lists them.
    private struct RecentWire: Decodable {
        let person: RecentRoomPerson?

        enum CodingKeys: String, CodingKey {
            case name, friend, presence
            case userID = "user_id"
            case avatarURL = "avatar_url"
            case lastSeenAt = "last_seen_at"
            case recentUntil = "recent_until"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let id = try? container.decodeIfPresent(UUID.self, forKey: .userID),
                  let until = (try? container.decodeIfPresent(String.self, forKey: .recentUntil))
                      .flatMap(HotMessDecoding.date(from:))
            else {
                person = nil
                return
            }
            let presence = (try? container.decodeIfPresent(String.self, forKey: .presence))
                .map { $0.uppercased() }
            person = RecentRoomPerson(
                person: RoomPerson(
                    id: id,
                    name: (try? container.decodeIfPresent(String.self, forKey: .name)).flatMap({ $0.nonBlank }),
                    avatarURL: (try? container.decodeIfPresent(String.self, forKey: .avatarURL)).flatMap({ $0.nonBlankURL }),
                    isFriend: (try? container.decodeIfPresent(Bool.self, forKey: .friend)) ?? false
                ),
                presence: presence == "PUSH" ? .push : .offline,
                lastSeenAt: (try? container.decodeIfPresent(String.self, forKey: .lastSeenAt))
                    .flatMap(HotMessDecoding.date(from:)),
                recentUntil: until
            )
        }
    }

    /// One of the roster's `friends`: an ID and a full name.
    private struct FriendWire: Decodable {
        let friend: Friend?

        enum CodingKeys: String, CodingKey {
            case name
            case userID = "user_id"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let id = try? container.decodeIfPresent(UUID.self, forKey: .userID),
                  let name = (try? container.decodeIfPresent(String.self, forKey: .name)).flatMap({ $0.nonBlank })
            else {
                friend = nil
                return
            }
            friend = Friend(id: id, name: name)
        }
    }
}

/// Someone in a chat room, as its roster and presence frames name them.
struct RoomPerson: Hashable, Sendable, Identifiable {
    let id: UUID
    /// "First L." for strangers, a full name for the user's friends. `nil`
    /// when the server didn't say.
    var name: String?
    var avatarURL: URL?
    /// The server says they're one of the user's friends.
    var isFriend = false
}

/// Someone who left a chat room in the last 30 minutes, or hosts an event on
/// there now, whom the room keeps listing, offline, until `recentUntil`
/// (for a host, the event's end, which can be hours away).
struct RecentRoomPerson: Hashable, Sendable, Identifiable {
    var person: RoomPerson
    /// `.push` when a notification still reaches them (the server only says
    /// so about the user's friends, and to admins), else `.offline`.
    var presence: PresenceState
    /// When they were last in the room. `nil` when unknown, or for a host
    /// who posted from Backstage without ever joining.
    var lastSeenAt: Date?
    /// When the room stops listing them.
    var recentUntil: Date

    var id: UUID { person.id }
}

private extension String {
    /// `nil` for an empty or all-whitespace string.
    var nonBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }

    var nonBlankURL: URL? {
        nonBlank.flatMap(URL.init(string:))
    }
}
