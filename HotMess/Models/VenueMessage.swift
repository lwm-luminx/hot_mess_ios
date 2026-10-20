//
//  VenueMessage.swift
//  HotMess
//

import AudienceKit
import Foundation

/// One line in a venue's chat room.
///
/// Hosts, the venue and staff can post more than text (see `ChatKind`). Every
/// message still carries `body`: the text itself, or a rich message in words
/// ("Shared an event: Sunset Social"), which is what previews and the app's
/// own echo matching use.
struct VenueMessage: Hashable, Sendable, Identifiable {
    let id: UUID
    /// The text, or a rich message's summary in words. The room's `message` key.
    let body: String
    let userID: UUID
    /// The sender's name as the server sends it: "First L." to anyone but
    /// their friends in room frames, or the venue's name for a post as the venue.
    let name: String?
    let avatarURL: URL?
    let sentAt: Date

    /// Who they are in the room, worked out by the server. `nil` for most people.
    var role: ChatRole? = nil
    var kind: ChatKind = .text
    /// An announcement's or special's headline.
    var title: String? = nil
    /// What they wrote, as written: a rich message's body or caption. Empty
    /// or `nil` when there's none.
    var written: String? = nil
    /// The photo of a photo message or an announcement.
    var photoURL: URL? = nil
    /// The event an event message shares.
    var event: SharedEvent? = nil
    /// When a special stops showing.
    var endsAt: Date? = nil
    /// The announcement pinned under the room's title.
    var isPinned = false
    /// Posted as the venue: `name` and `avatarURL` are the venue's.
    var postedAsVenue = false
    /// Posted by talent as their listing (role `host`): `name` and `avatarURL`
    /// are the person's, and this is which person.
    var personID: UUID? = nil
    /// Whether the sender can be reached now, where the API says (GraphQL
    /// previews). Room frames don't carry it; the room's roster does.
    var presence: PresenceState? = nil
    /// The song request or karaoke signup a request line made, with where it
    /// is in the queue. The room re-sends the line as the host works it.
    var request: ChatSongRequest? = nil

    init(
        id: UUID = UUID(),
        body: String,
        userID: UUID,
        name: String? = nil,
        avatarURL: URL? = nil,
        sentAt: Date = .now
    ) {
        self.id = id
        self.body = body
        self.userID = userID
        self.name = name
        self.avatarURL = avatarURL
        self.sentAt = sentAt
    }

    func isOutgoing(for currentUserID: UUID?) -> Bool {
        userID == currentUserID
    }

    /// A place, not a person: shown with the venue's photo in a rounded square
    /// and no presence. The server only gives the `venue` role to a post as the venue.
    var isFromPlace: Bool {
        postedAsVenue || role == .venue
    }

    /// A listing, not the human who typed it: the venue, or talent posting as
    /// themselves from Backstage. It has no presence, never takes a friend's
    /// name, and groups apart from the sender's own lines.
    var isFromListing: Bool {
        isFromPlace || personID != nil
    }

    /// Whether the room still shows it: a special stops at its end time.
    func isShowing(at date: Date = .now) -> Bool {
        guard kind == .special, let endsAt else { return true }
        return endsAt > date
    }
}

/// A sender's role in a room, set by the server, never chosen in the app.
enum ChatRole: String, Hashable, Sendable {
    /// Posting as the venue.
    case venue
    /// Talent posting as their listing: featured at the venue, or hosting
    /// one of its events.
    case host
    /// One of the audience's admins.
    case staff

    /// Room frames send `venue`, GraphQL `VENUE`.
    init?(wire: String) {
        self.init(rawValue: wire.lowercased())
    }
}

/// What a message is. Anything but `text` comes only from people with a role.
enum ChatKind: String, Hashable, Sendable {
    case text
    /// A title, a body and an optional photo. One per room can be pinned.
    case announcement
    /// One of the audience's events, with an optional caption.
    case event
    /// A photo with an optional caption.
    case photo
    /// A title and body that stop showing at `endsAt`.
    case special
    /// A song request or karaoke signup, anyone's in a venue's room, with
    /// their note to the host as its body.
    case request

    init?(wire: String) {
        self.init(rawValue: wire.lowercased())
    }
}

/// The song request or karaoke signup on a request line, as the room sends
/// it (the frame's `request`, GraphQL's `request { … }`): the song, who's
/// singing a signup, and where it is in the queue.
struct ChatSongRequest: Hashable, Sendable {
    let id: String
    let kind: SongRequest.Kind
    let title: String
    var artist: String? = nil
    /// Who's singing a karaoke signup; `nil` for a song request.
    var singer: String? = nil
    var state: SongRequest.State = .queued

    /// "Song request", "Karaoke signup".
    var label: String {
        kind == .song ? String(localized: "Song request") : String(localized: "Karaoke signup")
    }

    /// The request in words: "Dancing Queen by ABBA", or for a signup "Ada to
    /// sing Waterloo by ABBA".
    var headline: String {
        let song = artist.flatMap { $0.isEmpty ? nil : String(localized: "\(title) by \($0)") } ?? title
        guard kind != .song, let singer, !singer.isEmpty else { return song }
        return String(localized: "\(singer) to sing \(song)")
    }

    /// Where it stands, worded for its kind: "In the queue", "Playing now",
    /// "Played", "Skipped" for a song; "On the list", "Singing now", "Sang",
    /// "Passed" for a signup.
    var status: String {
        let song = kind == .song
        return switch state {
        case .queued: song ? String(localized: "In the queue") : String(localized: "On the list")
        case .up: song ? String(localized: "Playing now") : String(localized: "Singing now")
        case .done: song ? String(localized: "Played") : String(localized: "Sang")
        case .skipped: song ? String(localized: "Skipped") : String(localized: "Passed")
        case .withdrawn: String(localized: "Withdrawn")
        case .unknown: String(localized: "Requested")
        }
    }

    /// Played, sung, skipped or withdrawn: nothing more happens to it.
    var isFinished: Bool { !state.isOpen && state != .unknown }
}

/// The event an event message shares, as much of it as the room sends.
struct SharedEvent: Hashable, Sendable {
    let id: UUID
    let name: String?
    let startAt: Date?
}

extension PresenceState {
    /// The API's `ONLINE` / `PUSH` (or the room's lowercase form). Offline,
    /// and anything unknown, is `nil`: it draws nothing.
    init?(wire: String) {
        switch wire.lowercased() {
        case "online": self = .online
        case "push": self = .push
        default: return nil
        }
    }
}

extension VenueMessage {
    /// A chat line as the server broadcasts it, or as GraphQL's
    /// `chat { recentMessages }` returns it (aliased to the same keys).
    ///
    /// Only `message` and `user_id` are required: older frames carry nothing
    /// else, and a malformed optional field is dropped rather than failing
    /// the whole line.
    struct Payload: Decodable, Sendable {
        let id: UUID?
        let message: String
        let userID: UUID
        let name: String?
        let avatarURL: URL?
        let sentAt: Date?
        let role: ChatRole?
        let kind: ChatKind?
        let title: String?
        let body: String?
        let photoURL: URL?
        let event: SharedEvent?
        let endsAt: Date?
        let pinned: Bool
        let postedAsVenue: Bool
        let personID: UUID?
        let presence: PresenceState?
        let request: ChatSongRequest?

        enum CodingKeys: String, CodingKey {
            case id, message, name, role, kind, title, body, event, pinned, presence, request
            case userID = "user_id"
            case avatarURL = "avatar_url"
            case sentAt = "sent_at"
            case photoURL = "photo_url"
            case endsAt = "ends_at"
            case postedAsVenue = "posted_as_venue"
            case postedAsPerson = "posted_as_person"
            case personID = "person_id"
            case person
        }

        private enum PersonKeys: String, CodingKey {
            case id
        }

        private enum EventKeys: String, CodingKey {
            case id, name
            case startAt = "start_at"
        }

        private enum RequestKeys: String, CodingKey {
            case id, kind, title, artist, singer, state
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try? container.decodeIfPresent(UUID.self, forKey: .id)
            message = try container.decode(String.self, forKey: .message)
            userID = try container.decode(UUID.self, forKey: .userID)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            avatarURL = try container.decodeURLIfPresent(forKey: .avatarURL)
            sentAt = Self.date(in: container, forKey: .sentAt)

            role = (try? container.decodeIfPresent(String.self, forKey: .role)).flatMap { ChatRole(wire: $0) }
            kind = (try? container.decodeIfPresent(String.self, forKey: .kind)).flatMap { ChatKind(wire: $0) }
            title = try? container.decodeIfPresent(String.self, forKey: .title)
            body = try? container.decodeIfPresent(String.self, forKey: .body)
            photoURL = try? container.decodeURLIfPresent(forKey: .photoURL)
            endsAt = Self.date(in: container, forKey: .endsAt)
            pinned = (try? container.decodeIfPresent(Bool.self, forKey: .pinned)) ?? false
            postedAsVenue = (try? container.decodeIfPresent(Bool.self, forKey: .postedAsVenue)) ?? false
            // Room frames send `person_id`; GraphQL a `person { id }`.
            let postedAsPerson = (try? container.decodeIfPresent(Bool.self, forKey: .postedAsPerson)) ?? false
            let framePerson = try? container.decodeIfPresent(UUID.self, forKey: .personID)
            let nestedPerson = (try? container.nestedContainer(keyedBy: PersonKeys.self, forKey: .person))
                .flatMap { try? $0.decode(UUID.self, forKey: .id) }
            personID = postedAsPerson ? (framePerson ?? nestedPerson) : nil
            presence = (try? container.decodeIfPresent(String.self, forKey: .presence)).flatMap { PresenceState(wire: $0) }

            if (try? container.decodeNil(forKey: .event)) == false,
               let shared = try? container.nestedContainer(keyedBy: EventKeys.self, forKey: .event),
               let eventID = try? shared.decode(UUID.self, forKey: .id) {
                event = SharedEvent(
                    id: eventID,
                    name: try? shared.decodeIfPresent(String.self, forKey: .name),
                    startAt: (try? shared.decodeIfPresent(String.self, forKey: .startAt))
                        .flatMap { try? Date($0, strategy: .iso8601) }
                )
            } else {
                event = nil
            }

            // The room and GraphQL send it alike; one without an ID or a song is dropped.
            if (try? container.decodeNil(forKey: .request)) == false,
               let line = try? container.nestedContainer(keyedBy: RequestKeys.self, forKey: .request),
               let requestID = try? line.decode(String.self, forKey: .id),
               let songTitle = try? line.decode(String.self, forKey: .title) {
                let wire = { (key: RequestKeys) in ((try? line.decodeIfPresent(String.self, forKey: key)) ?? nil)?.uppercased() }
                request = ChatSongRequest(
                    id: requestID,
                    kind: wire(.kind).flatMap(SongRequest.Kind.init(rawValue:)) ?? .unknown,
                    title: songTitle,
                    artist: (try? line.decodeIfPresent(String.self, forKey: .artist)) ?? nil,
                    singer: (try? line.decodeIfPresent(String.self, forKey: .singer)) ?? nil,
                    state: wire(.state).flatMap(SongRequest.State.init(rawValue:)) ?? .unknown
                )
            } else {
                request = nil
            }
        }

        /// The room and GraphQL both send plain ISO 8601.
        private static func date<Key: CodingKey>(in container: KeyedDecodingContainer<Key>, forKey key: Key) -> Date? {
            (try? container.decodeIfPresent(String.self, forKey: key))
                .flatMap { try? Date($0, strategy: .iso8601) }
        }
    }

    init(payload: Payload) {
        self.init(
            id: payload.id ?? UUID(),
            body: payload.message,
            userID: payload.userID,
            name: payload.name,
            avatarURL: payload.avatarURL,
            sentAt: payload.sentAt ?? .now
        )
        role = payload.role
        kind = payload.kind ?? .text
        title = payload.title
        written = payload.body
        photoURL = payload.photoURL
        event = payload.event
        endsAt = payload.endsAt
        isPinned = payload.pinned
        postedAsVenue = payload.postedAsVenue
        personID = payload.personID
        presence = payload.presence
        request = payload.request
    }
}

/// A venue's or locale's `chat` mixin: whether the user can join its room
/// (`open`), and the room's last few lines, oldest first, a connection the
/// documents read as `recent_messages: recentMessages(limit: 3) { nodes { … } }`.
/// A missing field reads as closed, with no lines.
struct ChatMixin: Decodable, Sendable {
    let open: Bool
    let recentMessages: [VenueMessage]

    private enum CodingKeys: String, CodingKey {
        case open
        case recentMessages = "recent_messages"
    }

    private struct Lines: Decodable, Sendable { let nodes: [VenueMessage.Payload]? }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        open = try container.decodeIfPresent(Bool.self, forKey: .open) ?? false
        recentMessages = (try container.decodeIfPresent(Lines.self, forKey: .recentMessages)?.nodes ?? [])
            .map(VenueMessage.init(payload:))
    }
}
