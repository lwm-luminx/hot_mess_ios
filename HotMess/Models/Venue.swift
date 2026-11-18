//
//  Venue.swift
//  HotMess
//

import CoreLocation
import Foundation

struct Venue: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let address: String?
    let subtitle: String?
    let phone: String?
    let facebookID: FacebookID?
    let facebookLink: URL?
    /// Metres from the device, when the request carried a location.
    let distance: Double?
    let photoURL: URL?
    let bannerURL: URL?
    let point: GeoPoint?
    let isLiked: Bool
    /// Its opening hours and whether it's open now; nil when the document
    /// didn't ask.
    let hours: VenueHours?

    var coordinate: CLLocationCoordinate2D? { point?.coordinate }

    var facebookURL: URL? { facebookLink ?? facebookID?.profileURL }

    /// What to show under the venue's name in a list row.
    var summary: String {
        subtitle ?? address ?? String(localized: "Address unavailable")
    }

    /// `address`, `phone`, `facebook_id` and `is_liked` come in the venue's
    /// profile mixin (see `ListingProfile`).
    enum CodingKeys: String, CodingKey {
        case id, name, point, distance, profile
        case subtitle = "description"
        case photoURL = "photo_url"
        case bannerURL = "banner_url"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        distance = try container.decodeIfPresent(Double.self, forKey: .distance)
        photoURL = try container.decodeURLIfPresent(forKey: .photoURL)
        bannerURL = try container.decodeURLIfPresent(forKey: .bannerURL)
        point = try container.decodeIfPresent(GeoPoint.self, forKey: .point)
        // A missing profile mixin reads as no address, phone or Page.
        let profile = try container.decodeIfPresent(ListingProfile.self, forKey: .profile) ?? ListingProfile()
        address = profile.address
        phone = profile.phone
        facebookID = profile.facebookID
        facebookLink = profile.facebookLink
        isLiked = profile.isLiked
        hours = profile.hours
    }

    /// Writes the shape `init(from:)` reads, with the profile mixin.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encodeIfPresent(distance, forKey: .distance)
        try container.encodeIfPresent(photoURL, forKey: .photoURL)
        try container.encodeIfPresent(bannerURL, forKey: .bannerURL)
        try container.encodeIfPresent(point, forKey: .point)
        try container.encode(
            ListingProfile(address: address, phone: phone, facebookID: facebookID, facebookLink: facebookLink,
                           isLiked: isLiked, hours: hours),
            forKey: .profile
        )
    }

    init(
        id: UUID,
        name: String,
        address: String? = nil,
        subtitle: String? = nil,
        phone: String? = nil,
        facebookID: FacebookID? = nil,
        facebookLink: URL? = nil,
        distance: Double? = nil,
        photoURL: URL? = nil,
        bannerURL: URL? = nil,
        point: GeoPoint? = nil,
        isLiked: Bool = false,
        hours: VenueHours? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.subtitle = subtitle
        self.phone = phone
        self.facebookID = facebookID
        self.facebookLink = facebookLink
        self.distance = distance
        self.photoURL = photoURL
        self.bannerURL = bannerURL
        self.point = point
        self.isLiked = isLiked
        self.hours = hours
    }
}

/// A venue's opening hours and whether it's open now, from Google via the
/// API's `profile { places { hours } }`, worded by the server in the venue's
/// own time zone ("Open until 2 AM", "Opens at 4 PM").
struct VenueHours: Codable, Hashable, Sendable {
    /// OPEN, CLOSED, UNKNOWN, CLOSED_TEMPORARILY or CLOSED_PERMANENTLY.
    var status: String
    /// Nil when nobody knows.
    var isOpen: Bool?
    /// Nil when the hours are unknown.
    var label: String?
    /// The week, a line a day ("Monday: 4:00 PM – 2:00 AM").
    var lines: [String]

    enum CodingKeys: String, CodingKey {
        case status, label, lines
        case isOpen = "is_open"
    }

    init(status: String = "UNKNOWN", isOpen: Bool? = nil, label: String? = nil, lines: [String] = []) {
        self.status = status
        self.isOpen = isOpen
        self.label = label
        self.lines = lines
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "UNKNOWN"
        isOpen = try container.decodeIfPresent(Bool.self, forKey: .isOpen)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        lines = try container.decodeIfPresent([String].self, forKey: .lines) ?? []
    }
}

/// A venue's or person's `profile` mixin, as the documents alias it:
/// `profile { address phone social_links: socialLinks { nodes { … } }
/// facebook { facebook_id: facebookId is_liked: isLiked } }`. Each document
/// selects only what it shows, so a missing part reads as nil, no links or
/// not liked, and null link nodes are dropped.
struct ListingProfile: Codable, Hashable, Sendable {
    var address: String?
    var phone: String?
    /// The social links connection's nodes; nil when the document didn't ask.
    var socialLinks: [SocialLink]?
    /// From the facebook module's mixin, like `isLiked`.
    var facebookID: FacebookID?
    var facebookLink: URL?
    var isLiked: Bool
    /// From the places module's mixin: `places { hours }`.
    var hours: VenueHours?

    init(
        address: String? = nil,
        phone: String? = nil,
        socialLinks: [SocialLink]? = nil,
        facebookID: FacebookID? = nil,
        facebookLink: URL? = nil,
        isLiked: Bool = false,
        hours: VenueHours? = nil
    ) {
        self.hours = hours
        self.address = address
        self.phone = phone
        self.socialLinks = socialLinks
        self.facebookID = facebookID
        self.facebookLink = facebookLink
        self.isLiked = isLiked
    }

    enum CodingKeys: String, CodingKey {
        case address, phone, facebook, places
        case socialLinks = "social_links"
    }

    private struct Places: Codable, Hashable, Sendable { var hours: VenueHours? }

    private enum FacebookKeys: String, CodingKey {
        case facebookID = "facebook_id"
        case isLiked = "is_liked"
        case facebookLink = "link"
    }

    private enum ConnectionKeys: String, CodingKey { case nodes }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        if (try? container.decodeNil(forKey: .socialLinks)) == false {
            let connection = try container.nestedContainer(keyedBy: ConnectionKeys.self, forKey: .socialLinks)
            socialLinks = try connection.decodeIfPresent([SocialLink?].self, forKey: .nodes)?.compactMap { $0 } ?? []
        } else {
            socialLinks = nil
        }
        if (try? container.decodeNil(forKey: .facebook)) == false {
            let facebook = try container.nestedContainer(keyedBy: FacebookKeys.self, forKey: .facebook)
            facebookID = try facebook.decodeIfPresent(FacebookID.self, forKey: .facebookID)
            facebookLink = try facebook.decodeURLIfPresent(forKey: .facebookLink)
            isLiked = try facebook.decodeIfPresent(Bool.self, forKey: .isLiked) ?? false
        } else {
            facebookID = nil
            facebookLink = nil
            isLiked = false
        }
        hours = (try? container.decodeIfPresent(Places.self, forKey: .places))?.hours
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encodeIfPresent(phone, forKey: .phone)
        if let socialLinks {
            var connection = container.nestedContainer(keyedBy: ConnectionKeys.self, forKey: .socialLinks)
            try connection.encode(socialLinks, forKey: .nodes)
        }
        var facebook = container.nestedContainer(keyedBy: FacebookKeys.self, forKey: .facebook)
        try facebook.encodeIfPresent(facebookID, forKey: .facebookID)
        try facebook.encodeIfPresent(facebookLink, forKey: .facebookLink)
        try facebook.encode(isLiked, forKey: .isLiked)
        if let hours {
            try container.encode(Places(hours: hours), forKey: .places)
        }
    }
}

/// The payload of `/v1/venues` and `/v1/locales/{id}/venues`.
struct VenueCollection: Codable, Hashable, Sendable {
    let venues: [Venue]
    let envelope: GeoPolygon?

    init(venues: [Venue] = [], envelope: GeoPolygon? = nil) {
        self.venues = venues
        self.envelope = envelope
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        venues = try container.decodeIfPresent([Venue].self, forKey: .venues) ?? []
        envelope = try container.decodeIfPresent(GeoPolygon.self, forKey: .envelope)
    }

    enum CodingKeys: String, CodingKey {
        case venues, envelope
    }
}
