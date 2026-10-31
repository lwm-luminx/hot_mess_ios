//
//  VenuesViewModel.swift
//  HotMess
//

import AudienceKit
import CoreLocation
import Foundation
import MapKit
import Observation

/// A venue that has a position, ready to draw on a map.
struct VenuePin: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: VenuePin, rhs: VenuePin) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension VenueCollection {
    var pins: [VenuePin] {
        venues.compactMap { venue in
            venue.coordinate.map { VenuePin(id: venue.id, name: venue.name, coordinate: $0) }
        }
    }

    /// The region that frames the results: the server's envelope when it sends
    /// one, otherwise a box around the pins.
    var region: MKCoordinateRegion? {
        envelope?.region ?? MKCoordinateRegion.containing(pins.map(\.coordinate))
    }

    func region(including location: Coordinates?) -> MKCoordinateRegion? {
        guard let location else { return region }
        return MKCoordinateRegion.containing(pins.map(\.coordinate) + [
            CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        ])
    }

    /// The audience's visible venues from AudienceKit GraphQL, in the order the
    /// API lists them: the audience's order, with community spaces (places that
    /// host events but aren't venues to go out to) after the rest. Only venues
    /// in `localeID` are kept once the device's locale is known; until then
    /// every venue shows.
    init(audienceVenues: [AudienceKit.Venue], localeID: UUID?, resolve: (String?) -> URL?) {
        let visible = audienceVenues
            .filter { !$0.hidden }
            .filter { localeID == nil || RecordID.uuid($0.locale.id) == localeID }

        self.init(venues: visible.compactMap { Venue($0, resolve: resolve) })
    }

    /// The venues by city for the Everywhere list: `firstCity` leads, the
    /// rest follow by name, each keeping the audience's order.
    func byCity(first firstCity: String?) -> [VenueCityGroup] {
        let other = String(localized: "Elsewhere")
        var groups: [String: [Venue]] = [:]
        var cities: [String] = []
        for venue in venues {
            let city = venue.subtitle.flatMap { $0.isEmpty ? nil : $0 } ?? other
            if groups[city] == nil { cities.append(city) }
            groups[city, default: []].append(venue)
        }
        return cities
            .sorted { lhs, rhs in
                if (lhs == firstCity) != (rhs == firstCity) { return lhs == firstCity }
                if (lhs == other) != (rhs == other) { return rhs == other }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            .map { VenueCityGroup(city: $0, venues: groups[$0] ?? []) }
    }
}

/// One city's venues in the Everywhere list.
struct VenueCityGroup: Identifiable, Hashable, Sendable {
    let city: String
    let venues: [Venue]

    var id: String { city }
}

extension Venue {
    /// A list row's worth of venue from AudienceKit GraphQL. Detail screens
    /// still load the full venue over REST by its UUID.
    init?(_ venue: AudienceKit.Venue, resolve: (String?) -> URL?) {
        guard let id = RecordID.uuid(venue.id) else { return nil }

        self.init(
            id: id,
            name: venue.name,
            subtitle: venue.locale.name ?? venue.locale.label,
            photoURL: resolve(venue.page?.photoUrl ?? venue.photoUrl),
            bannerURL: resolve(venue.page?.bannerUrl ?? venue.bannerUrl),
            point: venue.location?.coordinate.map { GeoPoint(x: $0.longitude, y: $0.latitude) }
        )
    }
}

@MainActor
@Observable
final class VenuesViewModel {
    /// The venues in the device's city, or every venue until the city is known.
    private(set) var state: LoadState<VenueCollection> = .idle
    /// Every venue in the audience, whatever its city.
    private(set) var everywhere = VenueCollection()
    /// What's on at each venue now, or next, from the locale's events.
    private(set) var nextEvents: [UUID: Event] = [:]

    private let audienceKit: AudienceKitClient
    private let api: HotMessAPI

    init(audienceKit: AudienceKitClient, api: HotMessAPI) {
        self.audienceKit = audienceKit
        self.api = api
    }

    func load(localeID: UUID?) async {
        if state.value == nil { state = .loading }

        // The rows show without them, so a failure here only leaves them out.
        async let events = Self.upcomingEvents(api: api, localeID: localeID)
        do {
            let venues = try await audienceKit.venues()
            everywhere = VenueCollection(audienceVenues: venues, localeID: nil, resolve: audienceKit.url(for:))
            state = .loaded(VenueCollection(audienceVenues: venues, localeID: localeID, resolve: audienceKit.url(for:)))
            nextEvents = Self.nextEvents(await events)
        } catch is CancellationError {
        } catch let error as AudienceKitError {
            state = LoadState(catching: APIError(error))
        } catch {
            state = LoadState(catching: error)
        }
    }

    private nonisolated static func upcomingEvents(api: HotMessAPI, localeID: UUID?) async -> [Event] {
        guard let localeID else { return [] }
        return (try? await api.eventList(in: localeID)) ?? []
    }

    /// Each venue's soonest event that isn't over yet.
    nonisolated static func nextEvents(_ events: [Event], at date: Date = .now) -> [UUID: Event] {
        var next: [UUID: Event] = [:]
        for event in events {
            guard let venueID = event.venue?.id,
                  (event.endDate ?? event.startDate.addingTimeInterval(4 * 3600)) > date else { continue }
            if let current = next[venueID], current.startDate <= event.startDate { continue }
            next[venueID] = event
        }
        return next
    }
}
