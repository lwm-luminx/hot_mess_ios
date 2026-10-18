//
//  Now.swift
//  HotMess
//

import Foundation
import MapKit

/// What `reportLocation` says about where the user is, shaped for the Now screen.
///
/// The API returns only where the user is: the `venue` they're in, else their
/// `locale` and its `nearby_venues`. Everything else comes from those objects'
/// mixins (`friends`, `events`, chat) and the audience's `ping` feed, and the
/// title and hero are built here from the event, venue or locale.
///
/// `event` is the event the user is at, from an hour before it starts to an
/// hour after it ends. When there is one the screen leads with it rather than
/// its venue, which may be a host that isn't listed as a venue at all.
///
/// `venues` stays optional on purpose: a missing key means "we don't know where
/// you are, show your friends", while an empty array means "we do know, and
/// there is nothing nearby". The two cases render differently.
struct Now: Decodable, Hashable, Sendable {
    /// How many of the locale's upcoming events the screen lists.
    /// The document asks for this many (`HotMessAPI.Documents.localeEventLimit`).
    static let localeEventLimit = Int(HotMessAPI.Documents.localeEventLimit) ?? 5

    let title: String
    /// The event the user is at, when they're at one.
    let event: Event?
    let venue: Venue?
    let venues: [Venue]?
    let friends: [Friend]
    /// The last few lines of the venue's chat room, oldest first. The API
    /// only sends them to someone who is at the venue.
    let recentMessages: [VenueMessage]
    /// Tonight's cover at the venue the user is in, or nil when there's none.
    let coverCharge: CoverCharge?
    /// The user's cover tonight at the venue the user is in, paid or being paid.
    let viewerAdmission: Admission?
    /// The user's coat check tonight at the venue the user is in, paid or being paid.
    let viewerCoatCheck: Admission?
    /// Who is on at the venue the user is in right now.
    let onNow: OnNow
    /// The locale the user is in, or nearest.
    let locale: AppLocale?
    /// Whether the user can join the locale's chat room: they're out in the
    /// locale and not at a venue, or they're an admin.
    let localeChatOpen: Bool
    /// The last few lines of the locale's chat room, oldest first. The API
    /// only sends them to someone in the locale.
    let localeMessages: [VenueMessage]
    /// Where your friends have been lately, most friends first, when you
    /// aren't in a venue yourself.
    let friendVenues: [FriendVenue]
    let events: [Event]
    let imageURL: URL?
    /// The user's own Ping, while it runs.
    var myPing: Ping?
    /// Friends' active Pings, newest first.
    var friendPings: [Ping]

    var isNearVenues: Bool { venues != nil }

    var region: MKCoordinateRegion? {
        MKCoordinateRegion.containing((venues ?? []).compactMap(\.coordinate))
    }

    enum CodingKeys: String, CodingKey {
        case event, venue, locale, audience
        case nearbyVenues = "nearby_venues"
    }

    private enum VenueKeys: String, CodingKey {
        case events, friends, tickets, chat, people
    }

    private enum LocaleKeys: String, CodingKey {
        case id, name, events, friends, chat
        case bannerURL = "banner_url"
    }

    private enum AudienceKeys: String, CodingKey { case me }

    private enum MeKeys: String, CodingKey { case ping }

    private enum PingKeys: String, CodingKey {
        case myPing = "my_ping"
        case friendPings = "friend_pings"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let venue = try container.decodeIfPresent(Venue.self, forKey: .venue)
        self.venue = venue
        let event = try container.decodeIfPresent(Event.self, forKey: .event)
        self.event = event
        venues = try container.decodeIfPresent([Venue].self, forKey: .nearbyVenues)
        var venueEvents: [Event] = []
        var venueFriends: [Friend] = []
        if (try? container.decodeNil(forKey: .venue)) == false,
           let venueContainer = try? container.nestedContainer(keyedBy: VenueKeys.self, forKey: .venue) {
            // The chat and people mixins; missing reads as no lines and no one on.
            recentMessages = try venueContainer.decodeIfPresent(ChatMixin.self, forKey: .chat)?.recentMessages ?? []
            // The venue's cover mixin, inside its tickets mixin; missing reads
            // as no cover.
            let cover = try venueContainer.decodeIfPresent(TicketsMixin.self, forKey: .tickets)?.cover
            coverCharge = cover?.coverCharge
            viewerAdmission = cover?.viewerAdmission
            viewerCoatCheck = cover?.viewerCoatCheck
            onNow = (try? venueContainer.decodeIfPresent(VenuePeopleMixin.self, forKey: .people))?.onNow ?? []
            venueEvents = try venueContainer.decodeIfPresent(UpcomingEventsMixin.self, forKey: .events)?.upcoming ?? []
            venueFriends = try venueContainer.decodeIfPresent(FriendsMixin.self, forKey: .friends)?.list ?? []
        } else {
            recentMessages = []
            coverCharge = nil
            viewerAdmission = nil
            viewerCoatCheck = nil
            onNow = []
        }

        var localeName: String?
        var localeBanner: URL?
        var localeEvents: [Event] = []
        var localeFriends: FriendsMixin?
        if (try? container.decodeNil(forKey: .locale)) == false,
           let localeContainer = try? container.nestedContainer(keyedBy: LocaleKeys.self, forKey: .locale),
           let id = try localeContainer.decodeIfPresent(UUID.self, forKey: .id) {
            let name = try localeContainer.decodeIfPresent(String.self, forKey: .name) ?? ""
            locale = AppLocale(id: id, name: name)
            localeName = name
            let chat = try localeContainer.decodeIfPresent(ChatMixin.self, forKey: .chat)
            localeChatOpen = chat?.open ?? false
            localeMessages = chat?.recentMessages ?? []
            localeBanner = try localeContainer.decodeURLIfPresent(forKey: .bannerURL)
            localeEvents = try localeContainer.decodeIfPresent(UpcomingEventsMixin.self, forKey: .events)?.upcoming ?? []
            localeFriends = try localeContainer.decodeIfPresent(FriendsMixin.self, forKey: .friends)
        } else {
            locale = nil
            localeChatOpen = false
            localeMessages = []
        }

        if let event {
            title = event.name
            imageURL = event.bannerURL ?? venue?.bannerURL ?? localeBanner
        } else if let venue {
            title = venue.name
            imageURL = venue.bannerURL
        } else {
            title = localeName.map { String(localized: "Happening Now in \($0)") } ?? String(localized: "Happening Now")
            imageURL = localeBanner
        }

        if venue != nil {
            // The event the user is at leads the screen, so it isn't listed again.
            events = venueEvents.filter { $0.id != event?.id }
            friends = venueFriends
            friendVenues = []
        } else {
            events = Array(localeEvents.filter { $0.id != event?.id }.prefix(Self.localeEventLimit))
            friends = localeFriends?.list ?? []
            friendVenues = localeFriends?.venues ?? []
        }

        if (try? container.decodeNil(forKey: .audience)) == false,
           let audience = try? container.nestedContainer(keyedBy: AudienceKeys.self, forKey: .audience),
           (try? audience.decodeNil(forKey: .me)) == false,
           let me = try? audience.nestedContainer(keyedBy: MeKeys.self, forKey: .me),
           (try? me.decodeNil(forKey: .ping)) == false,
           let ping = try? me.nestedContainer(keyedBy: PingKeys.self, forKey: .ping) {
            myPing = try ping.decodeIfPresent(Ping.self, forKey: .myPing)
            friendPings = try ping.decodeIfPresent([Ping].self, forKey: .friendPings) ?? []
        } else {
            myPing = nil
            friendPings = []
        }
    }

    init(
        title: String,
        event: Event? = nil,
        venue: Venue? = nil,
        venues: [Venue]? = nil,
        friends: [Friend] = [],
        recentMessages: [VenueMessage] = [],
        coverCharge: CoverCharge? = nil,
        viewerAdmission: Admission? = nil,
        viewerCoatCheck: Admission? = nil,
        onNow: OnNow = [],
        locale: AppLocale? = nil,
        localeChatOpen: Bool = false,
        localeMessages: [VenueMessage] = [],
        friendVenues: [FriendVenue] = [],
        events: [Event] = [],
        imageURL: URL? = nil,
        myPing: Ping? = nil,
        friendPings: [Ping] = []
    ) {
        self.title = title
        self.event = event
        self.venue = venue
        self.venues = venues
        self.friends = friends
        self.recentMessages = recentMessages
        self.coverCharge = coverCharge
        self.viewerAdmission = viewerAdmission
        self.viewerCoatCheck = viewerCoatCheck
        self.onNow = onNow
        self.locale = locale
        self.localeChatOpen = localeChatOpen
        self.localeMessages = localeMessages
        self.friendVenues = friendVenues
        self.events = events
        self.imageURL = imageURL
        self.myPing = myPing
        self.friendPings = friendPings
    }
}

