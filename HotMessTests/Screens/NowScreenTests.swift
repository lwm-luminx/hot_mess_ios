//
//  NowScreenTests.swift
//  HotMessTests
//
//  Now hosted in a window against the stub API: with no position, at a venue
//  with nothing on, at an event, and when the API fails.
//

import CoreLocation
import Foundation
import SwiftUI
import Testing

@testable import HotMess

@MainActor
@Suite("Now screen", .serialized)
struct NowScreenTests {
    /// Somewhere the stub puts at Nyne.
    private static let nyne = CLLocationCoordinate2D(latitude: 47.6575, longitude: -117.4117)

    private func stub(now: String? = nil) -> StubAPI {
        let stub = StubAPI()
        stub.stubSignedInBasics()
        if let now { stub.on("ReportLocation", .data(now)) }
        // Tonight's side loads at a venue: no safety alerts, no pair-up, no show.
        stub.on("VenueSafety", .data(#"{"venues":{"venue":{"id":"\#(ScreenFixtures.venueID)","canSendSafetyAlert":false,"safetyStaffOnShift":false}}}"#))
        stub.on("VenuePairUp", .data(#"{"venues":{"venue":{"pairUp":null}}}"#))
        stub.on("VenuePhotos", .data(#"{"venues":{"venue":{"posts":{"photos":{"nodes":[]}}}}}"#))
        stub.tolerate("ClosestLocale", "Lineup", "VenueLineup", "Show", "VenueShow", "Locale", "LocalePosts",
                      "Posts", "Articles", "LocaleArticles", "Admissions", "SchemaFields", "IntrospectType")
        return stub
    }

    @Test("With no position, Now asks only for Pings and offers to turn location on")
    func noPosition() async throws {
        let stub = stub()
        let model = stub.appModel()
        let screen = host(NowScreen(), model: model)
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Going out tonight?"))
        #expect(screen.contains("Location is off"))
        #expect(screen.contains("Turn On Location"))
        #expect(stub.count("Pings") >= 1)
        #expect(stub.count("ReportLocation") == 0)
        stub.expectEverythingStubbed()
    }

    @Test("At a venue with nothing on, Now leads with the venue and its room")
    func atVenue() async throws {
        let stub = stub(now: ScreenFixtures.nowAtVenue)
        let model = stub.appModel()
        let screen = host(NowScreen(), model: model)
        defer { screen.tearDown() }

        await model.location.simulate(at: Self.nyne, venueName: "Nyne", allowed: true)
        #expect(await screen.waitFor("Pretending to be at Nyne"))
        #expect(await screen.waitFor("Open the chat at Nyne, 1 recent message"))
        #expect(screen.contains("Alex is here"))
        #expect(screen.contains("Tell your friends you're at Nyne."))
        #expect(!screen.contains("Location is off"))
        #expect(stub.count("ReportLocation") >= 1)
        let position = try #require(stub.last("ReportLocation")?.variables["position"] as? [String: Any])
        #expect(position.isEmpty == false)
        stub.expectEverythingStubbed()
    }

    @Test("At an event, Now is titled for the event")
    func atEvent() async throws {
        let stub = stub(now: ScreenFixtures.nowAtEvent)
        let model = stub.appModel()
        let screen = host(NowScreen(), model: model)
        defer { screen.tearDown() }

        await model.location.simulate(at: Self.nyne, venueName: "Nyne", allowed: true)
        #expect(await screen.waitFor("Bingo Night"))
        stub.expectEverythingStubbed()
    }

    @Test("Near venues but in none, Now lists what's nearby")
    func nearby() async throws {
        let stub = stub(now: ScreenFixtures.nowNearby)
        let model = stub.appModel()
        let screen = host(NowScreen(), model: model)
        defer { screen.tearDown() }

        await model.location.simulate(at: Self.nyne, venueName: "SoMa", allowed: true)
        #expect(await screen.waitFor("The Stud"))
        stub.expectEverythingStubbed()
    }

    @Test("When reporting the position fails, Now shows the error with Try Again")
    func failure() async throws {
        let stub = stub()
        stub.on("ReportLocation", .raw(status: 500, body: #"{"error":"boom"}"#))
        let model = stub.appModel()
        let screen = host(NowScreen(), model: model)
        defer { screen.tearDown() }

        await model.location.simulate(at: Self.nyne, venueName: "Nyne", allowed: true)
        // The first load (no position) already showed Pings, so a failed
        // refresh keeps them on screen rather than replacing them.
        await screen.settle(timeout: .seconds(1))
        #expect(stub.count("ReportLocation") >= 1)

        // A fresh screen whose first load fails shows the error.
        let fresh = host(NowScreen(), model: model)
        defer { fresh.tearDown() }
        #expect(await fresh.waitFor("Something went wrong"))
        #expect(fresh.contains("Try Again"))
        stub.expectEverythingStubbed()
    }

    @Test("Now at a venue draws in dark mode at a large accessibility text size")
    func darkLargeType() async throws {
        let stub = stub(now: ScreenFixtures.nowAtVenue)
        let model = stub.appModel()
        let screen = host(NowScreen(), model: model, colorScheme: .dark, dynamicType: .accessibility3)
        defer { screen.tearDown() }

        await model.location.simulate(at: Self.nyne, venueName: "Nyne", allowed: true)
        #expect(await screen.waitFor("Open the chat at Nyne"))
        #expect(screen.renderedSomething)
        stub.expectEverythingStubbed()
    }
}
