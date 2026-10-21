//
//  Post.swift
//  HotMess
//

import Foundation

/// A post by a venue or a talent listing: an announcement, a special, a poster
/// or photos that stays on their page, unlike chat. Hot Mess only reads posts
/// and comments on them; venues post from Velvet, talent from Backstage.
struct Post: Decodable, Identifiable, Hashable, Sendable {
    /// The event a post is on, for its "on {event}" line and chip.
    struct EventLink: Decodable, Hashable, Sendable {
        let id: UUID
        let name: String
        let startAt: Date?
    }

    let id: UUID
    let body: String
    /// The venue or the person, in full: listings are public pages.
    let posterName: String
    let posterAvatarURL: URL?
    /// "Venue", or talent's part on the event ("MC", "DJ", "Act", "Duet",
    /// "Troupe", "Host"); nil on their own page.
    let roleLabel: String?
    /// "Kiki Riot for House of Lux", on a troupe's post written by a member.
    let actingPersonName: String?
    let createdAt: Date
    let edited: Bool
    let pinned: Bool
    let commentsOpen: Bool
    var commentCount: Int
    let photos: [PostPhoto]
    let event: EventLink?
    /// The talent listing posting it; nil when the venue posted.
    let personID: UUID?
    /// The venue posting it, or a talent post's event venue.
    let venueID: UUID?

    /// Posted as a venue, not a person: a rounded-square face and the "Venue" tag.
    var isVenuePost: Bool { personID == nil }

    /// The poster's page.
    var posterRoute: AppRoute? {
        if let personID { return .person(personID) }
        return venueID.map(AppRoute.venue)
    }

    /// Who "Hide posts from" mutes.
    var poster: PostPoster? {
        if let personID { return .person(personID, name: posterName) }
        return venueID.map { .venue($0, name: posterName) }
    }

    /// What Share sends with the post's text: its poster's page, until
    /// hotmess.social has a page per post.
    var shareURL: URL? {
        if let personID { return URL(string: "https://hotmess.social/people/\(personID.uuidString.lowercased())") }
        return venueID.map { URL(string: "https://hotmess.social/venues/\($0.uuidString.lowercased())")! }
    }

    private enum CodingKeys: String, CodingKey {
        case id, body, posterName, roleLabel, actingPersonName, createdAt, edited, pinned, commentsOpen
        case commentCount, photos, event, person, venue
        case posterAvatarURL = "posterAvatarUrl"
    }

    private struct Ref: Decodable { let id: UUID }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        posterName = try container.decodeIfPresent(String.self, forKey: .posterName) ?? ""
        posterAvatarURL = try container.decodeURLIfPresent(forKey: .posterAvatarURL)
        roleLabel = try container.decodeIfPresent(String.self, forKey: .roleLabel)
        actingPersonName = try container.decodeIfPresent(String.self, forKey: .actingPersonName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        edited = try container.decodeIfPresent(Bool.self, forKey: .edited) ?? false
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        commentsOpen = try container.decodeIfPresent(Bool.self, forKey: .commentsOpen) ?? true
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        // A photo whose URL didn't come through is left out rather than drawn empty.
        photos = (try container.decodeIfPresent([PostPhoto].self, forKey: .photos) ?? []).filter { $0.url != nil }
        event = try container.decodeIfPresent(EventLink.self, forKey: .event)
        personID = try container.decodeIfPresent(Ref.self, forKey: .person)?.id
        venueID = try container.decodeIfPresent(Ref.self, forKey: .venue)?.id
    }

    /// The metadata line: "Pinned · 2h · Edited · on Drag Bingo". `showsPin`
    /// is off where pins don't float (the updates feed); `showsEvent` is off
    /// on the event's own page.
    func metadata(relativeTo now: Date = .now, showsPin: Bool = true, showsEvent: Bool = true) -> String {
        var parts: [String] = []
        if pinned, showsPin { parts.append(String(localized: "Pinned")) }
        parts.append(Self.relativeTime(createdAt, now: now))
        if edited { parts.append(String(localized: "Edited")) }
        if showsEvent, let event { parts.append(String(localized: "on \(event.name)")) }
        return parts.joined(separator: " · ")
    }

    /// "now", "5m", "2h", "3d", then the date.
    static func relativeTime(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return String(localized: "now")
        case ..<3600: return String(localized: "\(Int(seconds / 60))m")
        case ..<86400: return String(localized: "\(Int(seconds / 3600))h")
        case ..<(7 * 86400): return String(localized: "\(Int(seconds / 86400))d")
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

struct PostPhoto: Decodable, Hashable, Sendable {
    let url: URL?
    let altText: String?

    private enum CodingKeys: String, CodingKey { case url, altText }

    init(url: URL?, altText: String?) {
        self.url = url
        self.altText = altText
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeURLIfPresent(forKey: .url)
        altText = try container.decodeIfPresent(String.self, forKey: .altText)
    }
}

/// A comment on a post. The API names commenters as rooms do ("Aurora B."); the
/// app swaps in a friend's full name (`FriendDirectory`).
struct PostComment: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    let authorID: UUID
    let authorName: String
    let authorAvatarURL: URL?
    let body: String
    let createdAt: Date
    let viewerCanRemove: Bool

    private enum CodingKeys: String, CodingKey {
        case id, authorName, body, createdAt, viewerCanRemove
        case authorID = "authorId"
        case authorAvatarURL = "authorAvatarUrl"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        authorID = try container.decode(UUID.self, forKey: .authorID)
        authorName = try container.decodeIfPresent(String.self, forKey: .authorName) ?? ""
        authorAvatarURL = try container.decodeURLIfPresent(forKey: .authorAvatarURL)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        viewerCanRemove = try container.decodeIfPresent(Bool.self, forKey: .viewerCanRemove) ?? false
    }
}

/// A venue or a person whose posts someone can hide (`mutePostAuthor`).
enum PostPoster: Hashable, Sendable {
    case venue(UUID, name: String)
    case person(UUID, name: String)

    var name: String {
        switch self {
        case let .venue(_, name), let .person(_, name): name
        }
    }
}

/// Whose posts a list shows: the API's `PostsFrom`.
enum PostsFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all = "ALL"
    case venues = "VENUES"
    case talent = "TALENT"
    /// Posts on events the viewer RSVP'd going to.
    case going = "GOING"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .venues: String(localized: "Venues")
        case .talent: String(localized: "Talent")
        case .going: String(localized: "Going")
        }
    }
}

/// Whose posts a section or screen lists.
enum PostsSubject: Hashable, Sendable {
    /// The venue's own posts, on it and its events, pinned first.
    case venue(UUID)
    /// Posts on the event by its venue and the people on it.
    case event(UUID)
    /// The listing's own posts, pinned first.
    case person(UUID)
    /// The locale's updates from the last 14 days, newest first.
    case locale(AppLocale)

    /// Pins float above the rest everywhere but the locale feed.
    var floatsPins: Bool {
        if case .locale = self { return false }
        return true
    }
}
