//
//  MoreScreenTests.swift
//  HotMessTests
//
//  The rest of the tabs and sheets hosted against the stub API: the Ping
//  sheet, Me (settings), the venues and events lists, a venue's chat room and
//  the cover section.
//

import AudienceKit
import CoreLocation
import Foundation
import SwiftUI
import Testing

@testable import HotMess

enum MoreStubs {
    static let localeJSON = #"{"id":"\#(ScreenFixtures.localeID)","name":"Spokane","label":"Spokane","cityNames":["Spokane"],"bannerUrl":null}"#

    static func venueNode(id: String, name: String, order: Int) -> String {
        #"{"id":"\#(id)","name":"\#(name)","hidden":false,"order":\#(order),"photoUrl":null,"bannerUrl":null,"profile":null,"locale":\#(localeJSON),"location":null,"tags":[]}"#
    }

    static var venues: String {
        let nodes = [
            venueNode(id: ScreenFixtures.venueID, name: "Nyne", order: 1),
            venueNode(id: "2b3c4d5e-6f70-4182-9a3b-4c5d6e7f8091", name: "The Globe", order: 2),
        ]
        return #"{"venues":{"list":{"nodes":[\#(nodes.joined(separator: ","))]}}}"#
    }

    static var localeEvents: String {
        let events = [
            ScreenFixtures.event(name: "Bingo Night", startHours: 2, endHours: 5),
            ScreenFixtures.event(id: "8b7c6d5e-4f3a-4b2c-9d1e-0f9a8b7c6d5e", name: "Drag Brunch", startHours: 40, endHours: 44),
        ]
        return #"{"locale":{"events":{"upcoming":{"nodes":[\#(events.joined(separator: ","))]}}}}"#
    }

    static func stub() -> StubAPI {
        let stub = StubAPI()
        stub.stubSignedInBasics()
        stub.on("ClosestLocale", .data(#"{"closestLocale":\#(localeJSON)}"#))
        stub.on("LocaleEvents", .data(localeEvents))
        return stub
    }

    static let spokane = CLLocationCoordinate2D(latitude: 47.6588, longitude: -117.4260)
}

@MainActor
@Suite("Ping sheet", .serialized)
struct PingSheetTests {
    @Test("With nothing nearby, it still offers to send, to friends by default")
    func compose() async throws {
        let stub = MoreStubs.stub()
        stub.on("Venues", .data(#"{"venues":{"list":{"nodes":[]}}}"#))
        let screen = host(PingSheet(), model: stub.appModel())
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Send ping"))
        #expect(screen.contains("Ping your friends"))
        #expect(screen.contains("Where do you want to go?"))
        #expect(screen.contains("My friends"))
        #expect(screen.contains("Add a note (optional)"))
        #expect(stub.count("Pings") >= 1)
        stub.expectEverythingStubbed()
    }

    @Test("Draws in dark mode at a large accessibility size")
    func darkLargeType() async throws {
        let stub = MoreStubs.stub()
        stub.on("Venues", .data(MoreStubs.venues))
        let screen = host(PingSheet(), model: stub.appModel(), colorScheme: .dark, dynamicType: .accessibility3)
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Send ping"))
        stub.expectEverythingStubbed()
    }
}

@MainActor
@Suite("Me screen", .serialized)
struct SettingsScreenTests {
    private func stub() -> StubAPI {
        let stub = MoreStubs.stub()
        stub.on("ManagedListings", .error("No listings in the stub"))
        stub.on("PairUpPush", .data(#"{"me":{"pair_up_push":true}}"#))
        stub.on("RecentChatPush", .error("Not in the stub"))
        stub.on("ServerSwitch", .data(#"{"me":{"can_switch_server":false}}"#))
        stub.on("Tribes", .data(#"{"id":"a1","tribes":[],"me":{"self":{"id":"11111111-2222-4333-8444-555555555555","tribes":[]}}}"#))
        return stub
    }

    @Test("Shows who's signed in and the privacy and safety rows")
    func signedIn() async throws {
        let stub = stub()
        let model = stub.appModel()
        await model.session.restoreSession()
        #expect(model.session.isSignedIn)
        // Tall enough that the lazy List lays out Help and Safety down to Your
        // Safety Alerts (Find Help Nearby pushed it below a phone's fold).
        let screen = host(SettingsScreen(), model: model, size: CGSize(width: 402, height: 1600))
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Test Person"))
        #expect(screen.contains("Passes"))
        #expect(screen.contains("Getting Help at a Venue"))
        #expect(screen.contains("Your Safety Alerts"))
        stub.expectEverythingStubbed()
    }

    @Test("Before the session is checked it still draws, without a name")
    func restoring() async throws {
        let stub = stub()
        let screen = host(SettingsScreen(), model: stub.appModel(), colorScheme: .dark, dynamicType: .accessibility2)
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Passes"))
        #expect(!screen.contains("Test Person"))
        stub.expectEverythingStubbed()
    }
}

@MainActor
@Suite("Venues and events tabs", .serialized)
struct ListScreenTests {
    @Test("Venues lists the locale's venues in order")
    func venues() async throws {
        let stub = MoreStubs.stub()
        stub.on("Venues", .data(MoreStubs.venues))
        stub.on("ReportLocation", .data(ScreenFixtures.nowNearby))
        let model = stub.appModel()
        await model.location.simulate(at: MoreStubs.spokane, venueName: "Spokane", allowed: true)
        let screen = host(VenuesScreen(), model: model)
        defer { screen.tearDown() }

        #expect(await screen.waitFor("The Globe"))
        #expect(screen.contains("Nyne"))
        stub.expectEverythingStubbed()
    }

    @Test("Venues shows the last list at once while a slow API answers")
    func venuesFromCache() async throws {
        let cache = InMemoryGraphQLCache()
        let stub = MoreStubs.stub()
        stub.on("Venues", .data(MoreStubs.venues))
        let warm = host(VenuesScreen(), model: stub.appModel(graphQLCache: cache))
        #expect(await warm.waitFor("The Globe"))
        warm.tearDown()

        // Next launch: the API takes a minute, the saved list shows anyway.
        stub.on("Venues", .offline)
        stub.delay("Venues", by: .seconds(60))
        let screen = host(VenuesScreen(), model: stub.appModel(graphQLCache: cache))
        defer { screen.tearDown() }

        #expect(await screen.waitFor("The Globe"))
        #expect(screen.contains("Nyne"))
        #expect(!screen.contains("Something went wrong"))
    }

    @Test("Venues shows the error when the list can't be had")
    func venuesFailure() async throws {
        let stub = MoreStubs.stub()
        stub.on("Venues", .offline)
        let screen = host(VenuesScreen(), model: stub.appModel())
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Something went wrong"))
        #expect(screen.contains("Try Again"))
        stub.expectEverythingStubbed()
    }

    @Test("Events with no position asks for location")
    func eventsWithoutLocation() async throws {
        let stub = MoreStubs.stub()
        let screen = host(EventsScreen(), model: stub.appModel())
        defer { screen.tearDown() }

        #expect(await screen.waitFor("We need your location to find events near you."))
        stub.expectEverythingStubbed()
    }

    @Test("Events lists the locale's upcoming events")
    func events() async throws {
        let stub = MoreStubs.stub()
        stub.on("LocaleEvents", .data(MoreStubs.localeEvents))
        stub.on("ReportLocation", .data(ScreenFixtures.nowNearby))
        let model = stub.appModel()
        await model.location.simulate(at: MoreStubs.spokane, venueName: "Spokane", allowed: true)
        let screen = host(EventsScreen(), model: model)
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Drag Brunch"))
        #expect(screen.contains("Bingo Night"))
        #expect(stub.last("LocaleEvents")?.string("id")?.lowercased() == ScreenFixtures.localeID)
        stub.expectEverythingStubbed()
    }
}

@MainActor
@Suite("Venue chat screen", .serialized)
struct VenueChatScreenTests {
    @Test("Opens the room for the venue, signed in, with the terms agreed")
    func opens() async throws {
        let stub = MoreStubs.stub()
        let venue = try JSONDecoder.hotMess.decode(Venue.self, from: Data(ScreenFixtures.venue().utf8))
        let model = stub.appModel()
        await model.session.restoreSession()
        let screen = host(VenueChatScreen(venue: venue), model: model)
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Nyne"))
        #expect(stub.count("Safety") >= 1)
        #expect(screen.renderedSomething)
        stub.expectEverythingStubbed()
    }
}

@MainActor
@Suite("Cover section", .serialized)
struct CoverSectionTests {
    private let cover = CoverCharge(amount: Money(cents: 1_000), fee: Money(cents: 112), total: Money(cents: 1_112),
                                    night: "2026-11-14", from: "21:00", until: "02:00", payable: true)

    @Test("Tonight's payable cover shows the price, quantity and ways to pay")
    func payable() async throws {
        let stub = MoreStubs.stub()
        let screen = host(ScrollView {
            CoverSection(coverCharge: cover, isTonight: true, admission: nil, venueID: ScreenFixtures.venueUUID,
                         venueName: "Nyne")
        }, model: stub.appModel())
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Cover $11.12 tonight"))
        #expect(screen.contains("Quantity, 1 cover"))
        #expect(screen.contains("Pay with card"))
        stub.expectEverythingStubbed()
    }

    @Test("A paid cover shows the pass instead")
    func paid() async throws {
        let stub = MoreStubs.stub()
        let admission = Admission(id: "7d9f2c1e-3b4a-4e5f-8a6b-1c2d3e4f5a6b", status: .paid, night: "2026-11-14",
                                  total: Money(cents: 1_112), passSecret: "c2VjcmV0LWtleS1mb3ItaG90LW1lc3MtY292ZXI=")
        let screen = host(ScrollView {
            CoverSection(coverCharge: cover, isTonight: true, admission: admission, venueID: ScreenFixtures.venueUUID,
                         venueName: "Nyne")
        }, model: stub.appModel(), colorScheme: .dark)
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Show pass"))
        #expect(!screen.contains("Pay with card"))
        stub.expectEverythingStubbed()
    }

    @Test("Another night's cover can't be paid yet")
    func anotherNight() async throws {
        let stub = MoreStubs.stub()
        let screen = host(ScrollView {
            CoverSection(coverCharge: cover, isTonight: false, admission: nil, venueID: ScreenFixtures.venueUUID,
                         venueName: "Nyne")
        }, model: stub.appModel(), dynamicType: .accessibility3)
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Cover $11.12"))
        #expect(!screen.contains("Pay with card"))
        stub.expectEverythingStubbed()
    }

    @Test("A cover paid only at the door has no pay button")
    func atTheDoor() async throws {
        let stub = MoreStubs.stub()
        let door = CoverCharge(amount: Money(cents: 500), total: Money(cents: 500), night: "2026-11-14", payable: false)
        let screen = host(ScrollView {
            CoverSection(coverCharge: door, isTonight: true, admission: nil, venueID: ScreenFixtures.venueUUID,
                         venueName: "Nyne")
        }, model: stub.appModel())
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Cover $5"))
        #expect(!screen.contains("Pay with card"))
        stub.expectEverythingStubbed()
    }
}
