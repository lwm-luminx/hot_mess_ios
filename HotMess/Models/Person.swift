//
//  Person.swift
//  HotMess
//

import Foundation

struct Person: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let facebookID: FacebookID?
    let facebookLink: URL?
    let role: String?
    let isLiked: Bool
    let avatarURL: URL?
    let bannerURL: URL?

    var facebookURL: URL? { facebookLink ?? facebookID?.profileURL }

    /// `facebook_id` and `is_liked` come in the person's profile mixin (see
    /// `ListingProfile`).
    enum CodingKeys: String, CodingKey {
        case id, name, role, profile
        case avatarURL = "avatar_url"
        case bannerURL = "banner_url"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        avatarURL = try container.decodeURLIfPresent(forKey: .avatarURL)
        bannerURL = try container.decodeURLIfPresent(forKey: .bannerURL)
        // A missing profile mixin reads as no Page, not liked.
        let profile = try container.decodeIfPresent(ListingProfile.self, forKey: .profile) ?? ListingProfile()
        facebookID = profile.facebookID
        facebookLink = profile.facebookLink
        isLiked = profile.isLiked
    }

    /// Writes the shape `init(from:)` reads, with the profile mixin.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try container.encodeIfPresent(bannerURL, forKey: .bannerURL)
        try container.encode(ListingProfile(facebookID: facebookID, facebookLink: facebookLink, isLiked: isLiked), forKey: .profile)
    }

    init(
        id: UUID,
        name: String,
        facebookID: FacebookID? = nil,
        facebookLink: URL? = nil,
        role: String? = nil,
        isLiked: Bool = false,
        avatarURL: URL? = nil,
        bannerURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.facebookID = facebookID
        self.facebookLink = facebookLink
        self.role = role
        self.isLiked = isLiked
        self.avatarURL = avatarURL
        self.bannerURL = bannerURL
    }
}

/// `/v1/people/{id}` — a person plus everything hanging off them.
struct PersonDetail: Codable, Hashable, Sendable, Identifiable {
    let person: Person
    /// Their bio, or what an organization does, in their own words; nil when they have none.
    let about: String?
    let events: [Event]
    let socialLinks: [SocialLink]
    let tracks: [Track]
    /// The people this person is made of, such as a troupe's performers.
    let members: [Person]
    /// The people this person is part of, such as their troupes.
    let groups: [Person]

    var id: UUID { person.id }
    var name: String { person.name }

    /// Where fans can tip them (Cash App, Venmo), each opening that app.
    var tipLinks: [SocialLink] { socialLinks.filter { $0.tipApp != nil && $0.url != nil } }
    /// Their social profiles, without the tip links.
    var profileLinks: [SocialLink] { socialLinks.filter { $0.tipApp == nil } }

    enum CodingKeys: String, CodingKey {
        case events, music, members, groups, profile, description
    }

    init(from decoder: any Decoder) throws {
        person = try Person(from: decoder)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Missing (an older API) or blank reads as none.
        let description = try container.decodeIfPresent(String.self, forKey: .description)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        about = description?.isEmpty == false ? description : nil
        // The person's events mixin; tolerated when missing, which reads as none.
        events = try container.decodeIfPresent(UpcomingEventsMixin.self, forKey: .events)?.upcoming ?? []
        // Their links come through the profile mixin; missing reads as none.
        socialLinks = try container.decodeIfPresent(ListingProfile.self, forKey: .profile)?.socialLinks ?? []
        // Their tracks come through the music mixin; a missing one reads as none.
        tracks = try container.decodeIfPresent(MusicMixin.self, forKey: .music)?.tracks ?? []
        members = try container.decodeIfPresent([Person].self, forKey: .members) ?? []
        groups = try container.decodeIfPresent([Person].self, forKey: .groups) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        try person.encode(to: encoder)

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(about, forKey: .description)
        try container.encode(UpcomingEventsMixin(upcoming: events), forKey: .events)
        // The whole profile mixin again, as it replaces the person's own.
        try container.encode(
            ListingProfile(socialLinks: socialLinks, facebookID: person.facebookID, facebookLink: person.facebookLink, isLiked: person.isLiked),
            forKey: .profile
        )
        try container.encode(MusicMixin(tracks: tracks), forKey: .music)
        try container.encode(members, forKey: .members)
        try container.encode(groups, forKey: .groups)
    }

    init(
        person: Person,
        about: String? = nil,
        events: [Event] = [],
        socialLinks: [SocialLink] = [],
        tracks: [Track] = [],
        members: [Person] = [],
        groups: [Person] = []
    ) {
        self.person = person
        self.about = about
        self.events = events
        self.socialLinks = socialLinks
        self.tracks = tracks
        self.members = members
        self.groups = groups
    }
}

/// The `music` mixin on a person, read as `music { tracks { nodes { … } } }`:
/// their newest tracks, a connection. A missing or null connection reads as
/// no tracks, and null nodes are dropped.
private struct MusicMixin: Codable {
    let tracks: [Track]

    init(tracks: [Track]) {
        self.tracks = tracks
    }

    enum CodingKeys: String, CodingKey { case tracks }
    private enum ConnectionKeys: String, CodingKey { case nodes }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if (try? container.decodeNil(forKey: .tracks)) == false {
            let connection = try container.nestedContainer(keyedBy: ConnectionKeys.self, forKey: .tracks)
            tracks = try connection.decodeIfPresent([Track?].self, forKey: .nodes)?.compactMap { $0 } ?? []
        } else {
            tracks = []
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var connection = container.nestedContainer(keyedBy: ConnectionKeys.self, forKey: .tracks)
        try connection.encode(tracks, forKey: .nodes)
    }
}
