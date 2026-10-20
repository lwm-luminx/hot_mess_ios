//
//  Event.swift
//  HotMess
//

import Foundation

struct Event: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let startDate: Date
    let endDate: Date?
    let facebookID: FacebookID?
    let venue: Venue?
    let person: Person?
    let bannerURL: URL?
    let isFeatured: Bool
    var rsvp: RSVP
    let karaoke: KaraokeNight?
    var isKaraoke: Bool { karaoke != nil }

    var facebookURL: URL? { facebookID?.eventURL }

    /// What its share link is minted for (see `RecordShareLink`).
    var sharePath: String { "/events/\(id.uuidString.lowercased())" }

    /// Where an event with no venue yet is.
    static let toBeAnnounced = String(localized: "To be announced")

    /// "9:00 PM at The Stud", or "9:00 PM · To be announced" when the venue
    /// isn't set yet — the original force-unwrapped the venue here and
    /// crashed on venue-less events.
    var subtitle: String {
        let time = startDate.formatted(date: .omitted, time: .shortened)

        if let venue {
            return String(localized: "\(time) at \(venue.name)")
        }
        if let person {
            return String(localized: "\(time) with \(person.name) · \(Self.toBeAnnounced)")
        }
        return "\(time) · \(Self.toBeAnnounced)"
    }

    enum PhotoPriority {
        case venueFirst
        case personFirst
        case standard
    }

    /// Background photo for an event card:
    /// In a person view, event -> venue -> person (.venueFirst)
    /// In a venue view, event -> person -> venue (.personFirst)
    func photoURL(
        prioritizing: PhotoPriority = .standard,
        venueFallback: Venue? = nil,
        personFallback: Person? = nil
    ) -> URL? {
        let venueBg = venue?.bannerURL ?? venue?.photoURL ?? venueFallback?.bannerURL ?? venueFallback?.photoURL
        let personBg = person?.bannerURL ?? person?.avatarURL ?? personFallback?.bannerURL ?? personFallback?.avatarURL
        switch prioritizing {
        case .venueFirst:
            return bannerURL ?? venueBg ?? personBg
        case .personFirst:
            return bannerURL ?? personBg ?? venueBg
        case .standard:
            return bannerURL ?? venueBg ?? personBg
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, venue, person, rsvp, karaoke
        case startDate = "start_at"
        case endDate = "end_at"
        case facebookID = "facebook_id"
        case bannerURL = "banner_url"
        case isFeatured = "is_featured"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        facebookID = try container.decodeIfPresent(FacebookID.self, forKey: .facebookID)
        venue = try container.decodeIfPresent(EventVenueMixin.self, forKey: .venue)?.venue
        person = try container.decodeIfPresent(Person.self, forKey: .person)
        bannerURL = try container.decodeURLIfPresent(forKey: .bannerURL)
        isFeatured = try container.decodeIfPresent(Bool.self, forKey: .isFeatured) ?? false
        karaoke = try container.decodeIfPresent(KaraokeNight.self, forKey: .karaoke)
        // The event's rsvp mixin, read as `rsvp { mine }`; missing reads as undecided.
        rsvp = try container.decodeIfPresent(RSVPMixin.self, forKey: .rsvp)?.mine ?? .unsure
    }

    /// Writes the shape `init(from:)` reads, with `venue` as the venue mixin.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encodeIfPresent(facebookID, forKey: .facebookID)
        try container.encode(EventVenueMixin(venue: venue), forKey: .venue)
        try container.encodeIfPresent(person, forKey: .person)
        try container.encodeIfPresent(bannerURL, forKey: .bannerURL)
        try container.encode(isFeatured, forKey: .isFeatured)
        try container.encodeIfPresent(karaoke, forKey: .karaoke)
        try container.encode(RSVPMixin(mine: rsvp), forKey: .rsvp)
    }

    init(
        id: UUID,
        name: String,
        startDate: Date,
        endDate: Date? = nil,
        facebookID: FacebookID? = nil,
        venue: Venue? = nil,
        person: Person? = nil,
        bannerURL: URL? = nil,
        isFeatured: Bool = false,
        rsvp: RSVP = .unsure,
        karaoke: KaraokeNight? = nil
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.facebookID = facebookID
        self.venue = venue
        self.person = person
        self.bannerURL = bannerURL
        self.isFeatured = isFeatured
        self.rsvp = rsvp
        self.karaoke = karaoke
    }
}

/// An event's `venue` mixin: its venue, or nil while it is to be announced.
/// The API always sends the mixin; a missing one reads as no venue.
struct EventVenueMixin: Codable, Hashable, Sendable {
    /// The venue's name, or "To be announced".
    let name: String?
    let venue: Venue?

    init(venue: Venue?) {
        self.name = venue?.name ?? Event.toBeAnnounced
        self.venue = venue
    }

    enum CodingKeys: String, CodingKey { case name, venue }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        venue = try container.decodeIfPresent(Venue.self, forKey: .venue)
    }
}

/// The `events` mixin on a venue, locale or person: `upcoming`, soonest
/// first, a connection the documents read as `upcoming { nodes { … } }`.
/// Without `first` the connection holds every upcoming event. A missing or
/// null mixin or connection reads as no events.
struct UpcomingEventsMixin: Codable, Hashable, Sendable {
    let upcoming: [Event]

    init(upcoming: [Event] = []) {
        self.upcoming = upcoming
    }

    enum CodingKeys: String, CodingKey { case upcoming }
    private enum ConnectionKeys: String, CodingKey { case nodes }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if (try? container.decodeNil(forKey: .upcoming)) == false {
            let connection = try container.nestedContainer(keyedBy: ConnectionKeys.self, forKey: .upcoming)
            upcoming = try connection.decodeIfPresent([Event].self, forKey: .nodes) ?? []
        } else {
            upcoming = []
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var connection = container.nestedContainer(keyedBy: ConnectionKeys.self, forKey: .upcoming)
        try connection.encode(upcoming, forKey: .nodes)
    }
}

/// An event's `people` mixin: who is hosting it and its whole lineup, both
/// connections the documents read as `people { hosts { nodes { … } } lineup
/// { nodes { … } } }`. The lineup includes the hosts. A missing or null
/// connection reads as no one.
struct EventPeopleMixin: Codable, Hashable, Sendable {
    let hosts: [Person]
    let lineup: [Person]

    init(hosts: [Person] = [], lineup: [Person] = []) {
        self.hosts = hosts
        self.lineup = lineup
    }

    enum CodingKeys: String, CodingKey { case hosts, lineup }
    private enum ConnectionKeys: String, CodingKey { case nodes }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hosts = try Self.decodeConnection(container, forKey: .hosts)
        lineup = try Self.decodeConnection(container, forKey: .lineup)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var hostConnection = container.nestedContainer(keyedBy: ConnectionKeys.self, forKey: .hosts)
        try hostConnection.encode(hosts, forKey: .nodes)
        var lineupConnection = container.nestedContainer(keyedBy: ConnectionKeys.self, forKey: .lineup)
        try lineupConnection.encode(lineup, forKey: .nodes)
    }

    private static func decodeConnection(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> [Person] {
        guard container.contains(key), (try? container.decodeNil(forKey: key)) == false else { return [] }
        let connection = try container.nestedContainer(keyedBy: ConnectionKeys.self, forKey: key)
        return try connection.decodeIfPresent([Person].self, forKey: .nodes) ?? []
    }
}

/// `/v1/events/{id}` — an event plus who is hosting it and who else is on.
struct EventDetail: Codable, Hashable, Sendable, Identifiable {
    var event: Event
    /// Who is hosting it.
    let hosts: [Person]
    /// Who else is on: the lineup without the hosts.
    let people: [Person]
    /// The cover at its venue that night, or nil when there's none (or it
    /// sells tickets).
    let coverCharge: CoverCharge?
    /// The cover at its venue tonight, whatever night the event is, so the
    /// screen can tell whether the event's cover is tonight's.
    let venueCoverTonight: CoverCharge?
    /// The user's cover tonight at its venue, paid or being paid.
    let viewerAdmission: Admission?
    /// Friends' Pings that pick this event, from its ping mixin. Read from
    /// GraphQL only, so it isn't encoded.
    var friendPings: [Ping]

    var id: UUID { event.id }

    /// Whether the event's cover is the venue's cover tonight, so it can be
    /// paid now.
    var isCoverTonight: Bool {
        guard let coverCharge, let venueCoverTonight else { return false }
        return coverCharge.night == venueCoverTonight.night
    }

    enum CodingKeys: String, CodingKey {
        case people, tickets, ping
        case venueCover = "venue_cover"
    }

    /// `venue_cover` is the event's venue mixin again, holding only the
    /// venue's tickets mixin and the cover mixin inside it.
    private enum VenueMixinKeys: String, CodingKey { case venue }
    private enum VenueKeys: String, CodingKey { case tickets }

    init(from decoder: any Decoder) throws {
        event = try Event(from: decoder)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Who's hosting and who's on come through the people mixin; missing
        // reads as no one. The lineup includes the hosts, so they're taken out.
        let lineup = try container.decodeIfPresent(EventPeopleMixin.self, forKey: .people) ?? EventPeopleMixin()
        hosts = lineup.hosts
        let hostIDs = Set(lineup.hosts.map(\.id))
        people = lineup.lineup.filter { !hostIDs.contains($0.id) }
        coverCharge = try container.decodeIfPresent(TicketsMixin.self, forKey: .tickets)?.cover?.coverCharge

        var venueCover: CoverMixin?
        if (try? container.decodeNil(forKey: .venueCover)) == false,
           let mixin = try? container.nestedContainer(keyedBy: VenueMixinKeys.self, forKey: .venueCover),
           (try? mixin.decodeNil(forKey: .venue)) == false,
           let venue = try? mixin.nestedContainer(keyedBy: VenueKeys.self, forKey: .venue) {
            venueCover = try venue.decodeIfPresent(TicketsMixin.self, forKey: .tickets)?.cover
        }
        venueCoverTonight = venueCover?.coverCharge
        viewerAdmission = venueCover?.viewerAdmission
        // The ping mixin is null without a viewer or the ping module, which
        // reads as no Pings.
        friendPings = try container.decodeIfPresent(PingsResponse.self, forKey: .ping)?.friendPings ?? []
    }

    func encode(to encoder: any Encoder) throws {
        try event.encode(to: encoder)

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(EventPeopleMixin(hosts: hosts, lineup: hosts + people), forKey: .people)
    }

    init(
        event: Event,
        hosts: [Person] = [],
        people: [Person] = [],
        coverCharge: CoverCharge? = nil,
        venueCoverTonight: CoverCharge? = nil,
        viewerAdmission: Admission? = nil,
        friendPings: [Ping] = []
    ) {
        self.event = event
        self.hosts = hosts
        self.people = people
        self.coverCharge = coverCharge
        self.venueCoverTonight = venueCoverTonight
        self.viewerAdmission = viewerAdmission
        self.friendPings = friendPings
    }
}

/// An event's `rsvp` mixin, as the documents select it: `rsvp { mine }`, the
/// signed-in user's answer (`UNSURE` when signed out).
struct RSVPMixin: Codable, Hashable, Sendable {
    let mine: RSVP

    init(mine: RSVP) {
        self.mine = mine
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mine = try container.decodeIfPresent(RSVP.self, forKey: .mine) ?? .unsure
    }
}
