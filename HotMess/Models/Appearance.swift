//
//  Appearance.swift
//  HotMess
//

import Foundation

/// Someone on at a venue: hosting, DJing, performing or MCing, with or
/// without an event. GraphQL's `Venue.people.onNow` lists the ones on right now.
/// An act can be a duet or a group: `people` are all of them, `person` the first.
struct Appearance: Hashable, Sendable, Identifiable {
    let id: UUID
    let person: Person
    /// Everyone on the act, in billing order; just `person` from an older API.
    let people: [Person]
    /// The act's billing, like a duet's name, if it has one.
    let title: String?
    /// What they're doing. `nil` for a role this build doesn't know.
    let role: Role?
    let startsAt: Date?
    /// When they finish; `nil` until the night ends.
    let endsAt: Date?
    /// Whether it goes on in the lineup's order, when the venue advances the
    /// show, rather than at a set time. Its times then aren't a set.
    let inOrder: Bool

    enum Role: String, Hashable, Sendable {
        case host, dj, performer, mc

        /// GraphQL sends `DJ`, the lineup's own records `dj`.
        init?(wire: String) {
            self.init(rawValue: wire.lowercased())
        }

        /// Under their name in an On now row, beside `systemImage`, as
        /// Velvet's lineup shows it.
        var label: String {
            switch self {
            case .host: String(localized: "Host")
            case .dj: String(localized: "DJ")
            case .performer: String(localized: "Performer")
            case .mc: String(localized: "MC")
            }
        }

        /// The SF Symbol beside `label`, the same as Velvet's.
        var systemImage: String {
            switch self {
            case .host: "sparkles"
            case .dj: "headphones"
            case .performer: "theatermasks"
            case .mc: "music.mic"
            }
        }
    }

    /// "Trixie Mattel", "Ada & Bo", or the act's billing.
    var name: String {
        if let title, !title.isEmpty { return title }
        return people.map(\.name).formatted(.list(type: .and, width: .short))
    }

    /// Their set, "23:45 – close" until they have an end time, in the
    /// viewer's clock. `nil` without a start, or for an act on in the
    /// lineup's order.
    var hours: String? {
        guard let startsAt, !inOrder else { return nil }
        let end = endsAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? String(localized: "close")
        return "\(startsAt.formatted(date: .omitted, time: .shortened)) – \(end)"
    }

    init(id: UUID, person: Person, people: [Person]? = nil, title: String? = nil, role: Role?,
         startsAt: Date? = nil, endsAt: Date? = nil, inOrder: Bool = false) {
        self.id = id
        self.person = person
        self.people = people ?? [person]
        self.title = title
        self.role = role
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.inOrder = inOrder
    }
}

extension Appearance: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, person, people, title, role
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case startTiming = "start_timing"
        case endTiming = "end_timing"
    }

    private enum ConnectionKeys: String, CodingKey { case nodes }

    /// GraphQL's role for a karaoke signup on the lineup.
    static let singerRole = "SINGER"

    /// Only `id` and a `person` with a name are required; an unknown role or
    /// a malformed time is dropped rather than failing the appearance, and an
    /// older API's appearance (no people, no timing) is a set. A karaoke
    /// singer isn't an appearance here: it fails, so the lenient lists drop
    /// it (the venue page shows singers with AudienceKitUI's `KaraokeQueue`).
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if (try? container.decodeIfPresent(String.self, forKey: .role)) == Self.singerRole {
            throw DecodingError.dataCorruptedError(
                forKey: .role, in: container, debugDescription: "A karaoke singer isn't an appearance"
            )
        }
        id = try container.decode(UUID.self, forKey: .id)
        person = try container.decode(Person.self, forKey: .person)
        let others = (try? container.nestedContainer(keyedBy: ConnectionKeys.self, forKey: .people))
            .flatMap { try? $0.decode([LenientPerson].self, forKey: .nodes) }?
            .compactMap(\.person) ?? []
        people = others.isEmpty ? [person] : others
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        role = (try? container.decodeIfPresent(String.self, forKey: .role)).flatMap { Role(wire: $0) }
        startsAt = Self.date(in: container, forKey: .startsAt)
        endsAt = Self.date(in: container, forKey: .endsAt)
        let startTiming = try? container.decodeIfPresent(String.self, forKey: .startTiming)
        let endTiming = try? container.decodeIfPresent(String.self, forKey: .endTiming)
        inOrder = startTiming == "NONE" || startTiming == "SOFT" || endTiming == "ADVANCE"
    }

    /// GraphQL's ISO 8601, with or without the decoder's date strategy.
    private static func date(in container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Date? {
        (try? container.decodeIfPresent(String.self, forKey: key))
            .flatMap { try? Date($0, strategy: .iso8601) }
    }
}

/// What's on at a venue right now: the acts on (a collection of them), and,
/// when the venue runs its lineup as a show it advances, whether it's in an
/// intermission and which act is up next.
struct OnNow: RandomAccessCollection, Hashable, Sendable, ExpressibleByArrayLiteral {
    /// A break in the show, with its label ("Bar break") if it has one.
    struct Intermission: Hashable, Sendable {
        let id: UUID
        let title: String?
    }

    var acts: [Appearance]
    var intermission: Intermission?
    var upNext: Appearance?
    /// Tonight's whole running order, when the document asks for it (the
    /// venue page): empty from an older API or a night with nothing on it.
    var lineup: [LineupEntry]

    init(acts: [Appearance] = [], intermission: Intermission? = nil, upNext: Appearance? = nil,
         lineup: [LineupEntry] = []) {
        self.acts = acts
        self.intermission = intermission
        self.upNext = upNext
        self.lineup = lineup
    }

    init(arrayLiteral acts: Appearance...) {
        self.init(acts: acts)
    }

    var startIndex: Int { acts.startIndex }
    var endIndex: Int { acts.endIndex }
    subscript(position: Int) -> Appearance { acts[position] }

    /// Whether there's anything to show: someone on, a break, or who's next.
    var hasAnything: Bool { !acts.isEmpty || intermission != nil || upNext != nil }

    /// Whether `entry` is what advancing the show puts on next.
    func isUpNext(_ entry: LineupEntry) -> Bool { entry.state == .upcoming && entry.id == upNext?.id }
}

/// One entry in a venue night's running order (`Venue.people.runningOrder`):
/// an act or an intermission, and whether it's still to come, on, or done.
struct LineupEntry: Hashable, Sendable, Identifiable {
    enum State: String, Hashable, Sendable {
        case upcoming = "UPCOMING", on = "ON", done = "DONE"
    }

    enum Content: Hashable, Sendable {
        case act(Appearance)
        case intermission(OnNow.Intermission)
    }

    let content: Content
    let state: State

    var id: UUID {
        switch content {
        case .act(let appearance): appearance.id
        case .intermission(let intermission): intermission.id
        }
    }
}

extension LineupEntry: Decodable {
    private enum CodingKeys: String, CodingKey { case id, kind, title, state }

    /// An act needs a `person` with a name, as `Appearance` does; an unknown
    /// state reads as still to come.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try? container.decodeIfPresent(String.self, forKey: .kind)
        if kind == "INTERMISSION" {
            let id = try container.decode(UUID.self, forKey: .id)
            let title = try? container.decodeIfPresent(String.self, forKey: .title)
            content = .intermission(OnNow.Intermission(id: id, title: title))
        } else {
            content = try .act(Appearance(from: decoder))
        }
        let wire = try? container.decodeIfPresent(String.self, forKey: .state)
        state = wire.flatMap { State(rawValue: $0) } ?? .upcoming
    }
}

/// A venue's `people` mixin as the app asks for it: who is on there right
/// now, a connection the documents read as `people { on_now: onNow { nodes
/// { … } } }`, with what the show has on stage and up next. A missing or
/// malformed connection reads as no one.
struct VenuePeopleMixin: Decodable {
    let onNow: OnNow

    private enum CodingKeys: String, CodingKey {
        case onNow = "on_now"
        case onStage = "on_stage"
        case upNext = "up_next"
        case runningOrder = "running_order"
    }
    private enum ConnectionKeys: String, CodingKey { case nodes }
    /// Enough of `onStage` and `upNext` to tell an intermission from an act.
    private struct Entry: Decodable {
        let id: UUID
        let kind: String?
        let title: String?
    }

    init(onNow: OnNow = []) {
        self.onNow = onNow
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let connection = try? container.nestedContainer(keyedBy: ConnectionKeys.self, forKey: .onNow)
        let acts = connection?.decodeAppearances(forKey: .nodes) ?? []
        let stage = try? container.decodeIfPresent(Entry.self, forKey: .onStage)
        let intermission = stage.flatMap { $0.kind == "INTERMISSION" ? OnNow.Intermission(id: $0.id, title: $0.title) : nil }
        let next = try? container.decodeIfPresent(Entry.self, forKey: .upNext)
        let upNext: Appearance? = next?.kind == "INTERMISSION" ? nil : (try? container.decodeIfPresent(Appearance.self, forKey: .upNext)) ?? nil
        let order = try? container.nestedContainer(keyedBy: ConnectionKeys.self, forKey: .runningOrder)
        let entries = (try? order?.decodeIfPresent([LenientLineupEntry].self, forKey: .nodes)) ?? nil
        onNow = OnNow(acts: acts, intermission: intermission, upNext: upNext,
                      lineup: entries?.compactMap(\.entry) ?? [])
    }
}

extension KeyedDecodingContainer {
    /// A venue's `on_now`, each appearance decoded on its own so one bad entry
    /// (a person with no name yet) drops only itself. A missing or malformed
    /// list, as from an API without the field, is empty.
    func decodeAppearances(forKey key: Key) -> [Appearance] {
        (try? decodeIfPresent([LenientAppearance].self, forKey: key))?
            .compactMap(\.appearance) ?? []
    }
}

private struct LenientPerson: Decodable {
    let person: Person?

    init(from decoder: any Decoder) throws {
        person = try? Person(from: decoder)
    }
}

private struct LenientLineupEntry: Decodable {
    let entry: LineupEntry?

    init(from decoder: any Decoder) throws {
        entry = try? LineupEntry(from: decoder)
    }
}

private struct LenientAppearance: Decodable {
    let appearance: Appearance?

    init(from decoder: any Decoder) throws {
        appearance = try? Appearance(from: decoder)
    }
}
