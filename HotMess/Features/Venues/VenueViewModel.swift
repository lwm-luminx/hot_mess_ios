//
//  VenueViewModel.swift
//  HotMess
//

import Foundation
import Observation

/// A venue plus the events and friends shown alongside it on its screen.
struct VenueOverview: Sendable, Equatable {
    var venue: Venue
    /// Its banner images, in the order the hero rotates through them.
    var bannerPhotos: [URL] = []
    var events: [Event] = []
    var friends: [Friend] = []
    var socialLinks: [SocialLink] = []
    /// Whether the user can join the venue's chat room: they're at the venue,
    /// or they're an admin. The way in is hidden otherwise.
    var chatOpen = false
    /// The last few lines of the venue's chat room, oldest first. The API
    /// only sends them to someone who can read the room.
    var recentMessages: [VenueMessage] = []
    /// Tonight's cover, or nil when there's none.
    var coverCharge: CoverCharge?
    /// The user's cover tonight, paid or being paid.
    var viewerAdmission: Admission?
    /// The user's coat check tonight, paid or being paid.
    var viewerCoatCheck: Admission?
    /// Who is on there right now: hosting, DJing, performing or MCing.
    var onNow: OnNow = []
    /// Friends' Pings that pick this venue or one of its events.
    var friendPings: [Ping] = []
    /// The venue's own ordering page (e.g. its Toast online ordering), which
    /// the Order button opens; nil when it has none.
    var orderingURL: URL?

    /// What the hero rotates through: its banner (its Google photo when it
    /// has one) and then its banner images, else its own photo.
    var heroPhotos: [URL] {
        var seen = Set<URL>()
        let photos = ([venue.bannerURL].compactMap { $0 } + bannerPhotos).filter { seen.insert($0).inserted }
        return photos.isEmpty ? [venue.photoURL].compactMap { $0 } : photos
    }

    /// The next event, on the hero.
    var nextEvent: Event? { events.first }
    /// The two after it, shown near the top of the page.
    var comingUp: ArraySlice<Event> { events.dropFirst().prefix(2) }
    /// The events after those, at the bottom.
    var laterEvents: ArraySlice<Event> { events.dropFirst(3) }
}

@MainActor
@Observable
final class VenueViewModel {
    private(set) var state: LoadState<VenueOverview> = .idle

    private let api: HotMessAPI
    private let venueID: UUID
    private let friends: FriendDirectory?

    init(api: HotMessAPI, venueID: UUID, friends: FriendDirectory? = nil) {
        self.api = api
        self.venueID = venueID
        self.friends = friends
    }

    /// Fetches the venue and its events in one GraphQL request.
    func load() async {
        if state.value == nil { state = .loading }

        do {
            let overview = try await api.venue(venueID)
            friends?.remember(overview.friends)
            state = .loaded(overview)
        } catch is CancellationError {
        } catch {
            state = LoadState(catching: error)
        }
    }

    // MARK: - Pings

    private(set) var isUpdatingPings = false
    var pingError: String?

    /// Friends' running Pings that pick this venue or one of its events.
    var activePings: [Ping] {
        Ping.friendFeed(state.value?.friendPings ?? [], at: .now)
    }

    /// Whether the user is in on every friend's Ping here.
    func isJoinedHere(userID: UUID?) -> Bool {
        PingPlaceJoin.isJoined(activePings, userID: userID) { $0.targets(atVenue: self.venueID) }
    }

    /// "I'm in" on each friend's pick here that the user isn't in on yet.
    func joinHere(userID: UUID?) async {
        await updatePings { pings, api in
            try await PingPlaceJoin.join(pings, userID: userID, api: api) { $0.targets(atVenue: self.venueID) }
        }
    }

    func leaveHere(userID: UUID?) async {
        await updatePings { pings, api in
            try await PingPlaceJoin.leave(pings, userID: userID, api: api) { $0.targets(atVenue: self.venueID) }
        }
    }

    private func updatePings(_ action: ([Ping], HotMessAPI) async throws -> [Ping]) async {
        guard !isUpdatingPings, var overview = state.value else { return }
        isUpdatingPings = true
        defer { isUpdatingPings = false }

        do {
            for ping in try await action(activePings, api) {
                overview.friendPings = overview.friendPings.replacing(ping)
            }
            state = .loaded(overview)
        } catch {
            pingError = NowViewModel.message(for: error)
            await load()
        }
    }
}
