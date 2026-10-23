//
//  PingComposer.swift
//  HotMess
//

import AudienceKit
import Foundation
import Observation

/// A place the send sheet opens with already picked: "Ping here" on a
/// venue or event page.
enum PingSeed: Hashable, Sendable, Identifiable {
    case venue(Venue)
    case event(Event)

    var id: PingPlace { place }

    var place: PingPlace {
        switch self {
        case let .venue(venue): .venue(venue.id)
        case let .event(event): .event(event.id)
        }
    }
}

/// What the send sheet offers: tonight's events in the locale first, then
/// the locale's venues.
struct PingChoices: Hashable, Sendable {
    var events: [Event] = []
    var venues: [Venue] = []

    var isEmpty: Bool { events.isEmpty && venues.isEmpty }

    init(events: [Event] = [], venues: [Venue] = []) {
        self.events = events
        self.venues = venues
    }

    /// `events` limited to tonight, earliest first. A night runs until 5am,
    /// like the events calendar, so a 1am set is part of tonight.
    static func tonight(_ events: [Event], at date: Date = .now, calendar: Calendar = .current) -> [Event] {
        events
            .filter { isTonight($0, at: date, calendar: calendar) }
            .sorted { $0.startDate < $1.startDate }
    }

    static func isTonight(_ event: Event, at date: Date = .now, calendar: Calendar = .current) -> Bool {
        NightCalendar.night(of: event.startDate, calendar: calendar) == NightCalendar.night(of: date, calendar: calendar)
    }

    /// Whether `place` is one of the choices.
    func contains(_ place: PingPlace) -> Bool {
        switch place {
        case let .venue(id): venues.contains { $0.id == id }
        case let .event(id): events.contains { $0.id == id }
        }
    }

    /// The choices with `seed` in them, at the top of its list, when the
    /// lists didn't already have it.
    func including(_ seed: PingSeed?) -> PingChoices {
        var choices = self
        switch seed {
        case let .venue(venue):
            if !choices.venues.contains(where: { $0.id == venue.id }) { choices.venues.insert(venue, at: 0) }
        case let .event(event):
            if !choices.events.contains(where: { $0.id == event.id }) { choices.events.insert(event, at: 0) }
        case nil:
            break
        }
        return choices
    }

    /// The picks of a Ping being edited that the lists don't have (another
    /// night's lineup, a venue that's since been hidden), so they stay
    /// visible and can be unpicked.
    func including(_ targets: [PingTarget]) -> PingChoices {
        var choices = self
        for target in targets {
            if let event = target.event, !choices.events.contains(where: { $0.id == event.id }) {
                choices.events.append(event)
            } else if target.event == nil, let venue = target.venue, !choices.venues.contains(where: { $0.id == venue.id }) {
                choices.venues.append(venue)
            }
        }
        return choices
    }
}

/// The send sheet's state: what can be picked, what is picked, the note and
/// who can see it. Opening it while you have a Ping edits that Ping.
@MainActor
@Observable
final class PingComposer {
    private(set) var state: LoadState<PingChoices> = .idle
    /// Picks in the order they were made.
    private(set) var selection: [PingPlace] = []
    var note = ""
    var reach: PingReach = .friends
    /// The user's running Ping, when the sheet edits it.
    private(set) var editing: Ping?
    private(set) var isSending = false
    var errorMessage: String?

    private let api: HotMessAPI
    private let audienceKit: AudienceKitClient
    private let localeID: UUID?
    private let seed: PingSeed?
    /// A place to pick by ID when the lists have it, for a screen that has
    /// only the ID (a chat room's venue).
    private let place: PingPlace?

    init(api: HotMessAPI, audienceKit: AudienceKitClient, localeID: UUID?, seed: PingSeed?, place: PingPlace? = nil) {
        self.api = api
        self.audienceKit = audienceKit
        self.localeID = localeID
        self.seed = seed
        self.place = place
    }

    var isEditing: Bool { editing != nil }

    func isSelected(_ place: PingPlace) -> Bool { selection.contains(place) }

    func toggle(_ place: PingPlace) {
        if let index = selection.firstIndex(of: place) {
            selection.remove(at: index)
        } else {
            selection.append(place)
        }
    }

    func load() async {
        guard state.value == nil else { return }
        state = .loading

        async let mine = loadMyPing()
        async let events = loadTonightsEvents()
        async let venues = loadVenues()
        let (ping, tonight, places) = await (mine, events, venues)

        var choices = PingChoices(events: tonight, venues: places)
        if let ping {
            editing = ping
            selection = ping.places
            note = ping.note ?? ""
            reach = ping.reach
            choices = choices.including(ping.targets)
        }
        if let seed {
            choices = choices.including(seed)
            if !selection.contains(seed.place) { selection.append(seed.place) }
        }
        if let place, !selection.contains(place), choices.contains(place) {
            selection.append(place)
        }

        state = .loaded(choices)
    }

    /// Sends the Ping (or saves the edit) and returns it, or `nil` with
    /// `errorMessage` set.
    func send() async -> Ping? {
        guard !isSending else { return nil }
        isSending = true
        defer { isSending = false }

        do {
            return try await api.sendPing(places: selection, note: note, localeID: localeID, reach: reach)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    // MARK: - Loading

    private func loadMyPing() async -> Ping? {
        (try? await api.pings())?.myPing
    }

    private func loadTonightsEvents() async -> [Event] {
        guard let localeID else { return [] }
        let events = (try? await api.eventList(in: localeID)) ?? []
        return PingChoices.tonight(events)
    }

    private func loadVenues() async -> [Venue] {
        guard let venues = try? await audienceKit.venues() else { return [] }
        return VenueCollection(audienceVenues: venues, localeID: localeID, resolve: audienceKit.url(for:)).venues
    }
}
