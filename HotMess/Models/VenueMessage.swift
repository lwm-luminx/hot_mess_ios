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
    /// The prompt a `prompt` line puts to the room, with its place in the
    /// night's prompts.
    var prompt: ChatPrompt? = nil
    /// The prompt a text line answers, if it does: it gets a "Prompt" label.
    var promptID: String? = nil
    /// Posted as the room's audience, like a prompt: the audience's name and
    /// mark, never a person, with no presence.
    var postedAsAudience = false
    /// The tribes the user and the sender both picked, for the "You're both"
    /// mark. `nil` when the room didn't say (it's only asked for where the
    /// API has tribes); never anyone's other tribes.
    var sharedTribes: [SharedTribe]? = nil
    /// Who it's from as the server says (`sender { kind }`, the frame's
    /// `sender_kind`). Older servers don't say; `sender` works it out then.
    var senderKind: ChatSenderKind? = nil
    /// Whether a persona's listing has a People page for its badge to open.
    /// `nil` when the server didn't say.
    var personHasPage: Bool? = nil

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
        isFromPlace || personID != nil || isFromAudience
    }

    /// The audience talking (a prompt), not the venue or a person: drawn with
    /// the audience's mark, no RoleTag and no presence, and nobody to block.
    var isFromAudience: Bool {
        postedAsAudience || kind == .prompt
    }

    /// Who it's from: what the server sent, else worked out from the older
    /// flags (a server that doesn't send it never sends a bot).
    var sender: ChatSenderKind {
        if let senderKind { return senderKind }
        if isFromAudience { return .system }
        if isFromPlace { return .venue }
        if personID != nil { return .persona }
        return .member
    }

    /// A rotating prompt, which the room shows under its title (PromptBar)
    /// rather than in the thread.
    var isPinnedPrompt: Bool {
        kind == .prompt && prompt?.shownAs == .pinned
    }

    /// Whether the room still shows it: a special stops at its end time.
    func isShowing(at date: Date = .now) -> Bool {
        guard kind == .special, let endsAt else { return true }
        return endsAt > date
    }
}

/// Who a chat line is from (the API's `ChatSenderKind`), which sets how it's
/// drawn. More may come: one the app doesn't know draws as a member.
enum ChatSenderKind: String, Hashable, Sendable {
    /// The room itself: a centred line with no avatar.
    case system
    /// Software with a name, like Glam: its own art with no border or fill,
    /// the sparkles over it, and a Bot tag.
    case bot
    /// Someone posting as the venue: a squarer avatar, a step larger.
    case venue
    /// Someone posting as a listing, like a host: a ringed circle and a role
    /// badge that opens their page.
    case persona
    /// Anyone as themself.
    case member

    /// GraphQL sends `BOT`, the room `bot`.
    init?(wire: String) {
        self.init(rawValue: wire.lowercased())
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
    /// One of an event's chat prompts (`prompt`), posted as the audience.
    case prompt

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

/// The prompt a `prompt` line puts to the room (GraphQL's `ChatPromptFrame`,
/// the frame's `prompt`): what it asks, a trivia answer to hide until it's
/// tapped or `revealAt`, how it went up, and where it falls in the night.
struct ChatPrompt: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        /// Something to talk about with the people around you.
        case conversation
        /// A question with an answer.
        case trivia
    }

    enum ShownAs: String, Hashable, Sendable {
        /// Rotated in, under the room's title until the next one.
        case pinned
        /// Dropped into a quiet room as a card.
        case card
    }

    /// What answers send as `promptId`.
    let id: String
    var kind: Kind = .conversation
    let text: String
    /// A trivia question's answer.
    var answer: String? = nil
    /// When the answer shows for everyone.
    var revealAt: Date? = nil
    var shownAs: ShownAs = .pinned
    /// Which prompt of the night it is, from 1, out of at most `total`.
    var number: Int? = nil
    var total: Int? = nil
    /// When the next one rotates in, if one will.
    var nextAt: Date? = nil

    var isTrivia: Bool { kind == .trivia }

    /// "Prompt" or "Trivia": the label on its answers and its card.
    var label: String {
        isTrivia ? String(localized: "Trivia") : String(localized: "Prompt")
    }

    /// "2 of 6", when the room says.
    var position: String? {
        guard let number, number > 0, let total, total >= number else { return nil }
        return String(localized: "\(number) of \(total)")
    }

    /// The PromptBar's overline: "Tonight's prompt · 2 of 6", or "Trivia · 3 of 6".
    var overline: String {
        let name = isTrivia ? String(localized: "Trivia") : String(localized: "Tonight's prompt")
        guard let position else { return name }
        return "\(name) · \(position)"
    }

    /// Whether a trivia answer shows for everyone by `date`.
    func isRevealed(at date: Date) -> Bool {
        guard let revealAt else { return false }
        return revealAt <= date
    }
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
        let prompt: ChatPrompt?
        let promptID: String?
        let postedAsAudience: Bool
        let sharedTribes: [SharedTribe]?
        let senderKind: ChatSenderKind?
        let personHasPage: Bool?

        enum CodingKeys: String, CodingKey {
            case id, message, name, role, kind, title, body, event, pinned, presence, request, prompt, sender
            case senderKind = "sender_kind"
            case hasPage = "has_page"
            case promptID = "prompt_id"
            case postedAsAudience = "posted_as_audience"
            case sharedTribes = "shared_tribes"
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

        private enum SenderKeys: String, CodingKey {
            case kind
            case hasPage = "has_page"
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

        private enum PromptKeys: String, CodingKey {
            case id, kind, text, answer, number, total
            case revealAt = "reveal_at"
            case shownAs = "shown_as"
            case nextAt = "next_at"
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

            // Room frames send `sender_kind` and `has_page`; GraphQL a
            // `sender { kind has_page: hasPage }`.
            let sender = try? container.nestedContainer(keyedBy: SenderKeys.self, forKey: .sender)
            senderKind = ((try? container.decodeIfPresent(String.self, forKey: .senderKind)) ?? nil)
                .flatMap { ChatSenderKind(wire: $0) }
                ?? ((try? sender?.decodeIfPresent(String.self, forKey: .kind)) ?? nil).flatMap { ChatSenderKind(wire: $0) }
            personHasPage = ((try? container.decodeIfPresent(Bool.self, forKey: .hasPage)) ?? nil)
                ?? ((try? sender?.decodeIfPresent(Bool.self, forKey: .hasPage)) ?? nil)

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

            // The room sends `prompt_id`, GraphQL `promptId` aliased to it.
            promptID = Self.identifier(in: container, forKey: .promptID)
            postedAsAudience = (try? container.decodeIfPresent(Bool.self, forKey: .postedAsAudience)) ?? false
            sharedTribes = (try? container.decodeIfPresent([GraphQLCable.Lenient<SharedTribe>].self, forKey: .sharedTribes))?
                .map { $0.compactMap(\.value) }

            // GraphQL's uppercase enums or the room's lowercase; one without an
            // ID or a question is dropped, and the line shows as its text.
            if (try? container.decodeNil(forKey: .prompt)) == false,
               let frame = try? container.nestedContainer(keyedBy: PromptKeys.self, forKey: .prompt),
               let frameID = Self.identifier(in: frame, forKey: .id),
               let text = try? frame.decode(String.self, forKey: .text) {
                let wire = { (key: PromptKeys) in ((try? frame.decodeIfPresent(String.self, forKey: key)) ?? nil)?.lowercased() }
                let answer = (try? frame.decodeIfPresent(String.self, forKey: .answer)) ?? nil
                prompt = ChatPrompt(
                    id: frameID,
                    kind: wire(.kind).flatMap(ChatPrompt.Kind.init(rawValue:)) ?? .conversation,
                    text: text,
                    answer: answer.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 },
                    revealAt: Self.date(in: frame, forKey: .revealAt),
                    shownAs: wire(.shownAs).flatMap(ChatPrompt.ShownAs.init(rawValue:)) ?? .pinned,
                    number: (try? frame.decodeIfPresent(Int.self, forKey: .number)) ?? nil,
                    total: (try? frame.decodeIfPresent(Int.self, forKey: .total)) ?? nil,
                    nextAt: Self.date(in: frame, forKey: .nextAt)
                )
            } else {
                prompt = nil
            }
        }

        /// An ID as a string, or a number from a server that sends one.
        private static func identifier<Key: CodingKey>(in container: KeyedDecodingContainer<Key>, forKey key: Key) -> String? {
            if let string = try? container.decodeIfPresent(String.self, forKey: key) {
                return string.isEmpty ? nil : string
            }
            if let number = try? container.decodeIfPresent(Int.self, forKey: key) {
                return String(number)
            }
            return nil
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
        prompt = payload.prompt
        promptID = payload.promptID
        postedAsAudience = payload.postedAsAudience
        sharedTribes = payload.sharedTribes
        senderKind = payload.senderKind
        personHasPage = payload.personHasPage
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
