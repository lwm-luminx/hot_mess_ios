//
//  VenuesListTests.swift
//  HotMessTests
//

import AudienceKit
import Foundation
import Testing

@testable import HotMess

@Suite("Venues list")
struct VenueCollectionLocaleTests {
    private let seattle = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let portland = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func venue(_ name: String, locale: UUID, city: String = "Locale", order: Int = 0,
                       hidden: Bool = false) throws -> AudienceKit.Venue {
        let json = """
        {"id": "\(UUID().uuidString)", "name": "\(name)", "hidden": \(hidden), "order": \(order),
         "locale": {"id": "\(locale.uuidString)", "name": "\(city)"}}
        """
        return try JSONDecoder().decode(AudienceKit.Venue.self, from: Data(json.utf8))
    }

    @Test("Shows only venues in the current locale")
    func filtersToLocale() throws {
        let venues = [
            try venue("R Place", locale: seattle, order: 1),
            try venue("Crush", locale: portland),
            try venue("Hidden", locale: seattle, hidden: true),
            try venue("Neighbours", locale: seattle, order: 2)
        ]

        let collection = VenueCollection(audienceVenues: venues, localeID: seattle) { _ in nil }

        #expect(collection.venues.map(\.name) == ["R Place", "Neighbours"])
    }

    @Test("Keeps the API's order, community spaces after the venues to go out to")
    func keepsServerOrder() throws {
        // The API lists a community space last even when it's first in the audience's order.
        let venues = [
            try venue("Neighbours", locale: seattle, order: 2),
            try venue("Utah Pride Center", locale: seattle, order: 1)
        ]

        let collection = VenueCollection(audienceVenues: venues, localeID: seattle) { _ in nil }

        #expect(collection.venues.map(\.name) == ["Neighbours", "Utah Pride Center"])
    }

    @Test("Shows every visible venue until the locale is known")
    func showsAllWithoutLocale() throws {
        let venues = [try venue("Neighbours", locale: seattle), try venue("Crush", locale: portland)]

        let collection = VenueCollection(audienceVenues: venues, localeID: nil) { _ in nil }

        #expect(collection.venues.count == 2)
    }

    @Test("Everywhere groups venues by city, the device's city first")
    func groupsByCity() throws {
        let venues = [
            try venue("Crush", locale: portland, city: "Portland"),
            try venue("R Place", locale: seattle, city: "Seattle", order: 1),
            try venue("Neighbours", locale: seattle, city: "Seattle", order: 2)
        ]

        let groups = VenueCollection(audienceVenues: venues, localeID: nil) { _ in nil }.byCity(first: "Seattle")

        #expect(groups.map(\.city) == ["Seattle", "Portland"])
        #expect(groups.first?.venues.map(\.name) == ["R Place", "Neighbours"])
    }
}
