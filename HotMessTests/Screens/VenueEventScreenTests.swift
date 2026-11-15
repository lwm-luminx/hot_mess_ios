//
//  VenueEventScreenTests.swift
//  HotMessTests
//
//  A venue's page and an event's page hosted against the stub API, and their
//  view models on their own: loading, loaded, not found, failed, and an RSVP
//  that the API refuses rolling back.
//

import Foundation
import SwiftUI
import Testing

@testable import HotMess

enum VenueEventStubs {
    static func venueResponse(events: [String] = [ScreenFixtures.event(startHours: 26, endHours: 30)]) -> String {
        #"{"venues":{"venue":\#(ScreenFixtures.venue(events: events))}}"#
    }

    static func eventResponse(rsvp: String = "null", hosts: String = "[]") -> String {
        let event = ScreenFixtures.event(startHours: 2, endHours: 6, rsvp: rsvp).dropLast()
        return #"{"events":{"event":\#(event),"people":{"hosts":{"nodes":\#(hosts)},"organizers":{"nodes":[]},"lineup":{"nodes":\#(hosts)}},"ping":{"friend_pings":[]}}}}"#
    }

    static let host = #"[{"id":"7d6c5b4a-3928-4170-8a6b-5c4d3e2f1a0b","name":"Miss Coco","avatar_url":null,"banner_url":null,"profile":null}]"#

    static func venueStub() -> StubAPI {
        let stub = StubAPI()
        stub.stubSignedInBasics()
        stub.on("VenueSafety", .data(#"{"venues":{"venue":{"id":"\#(ScreenFixtures.venueID)","canSendSafetyAlert":true,"safetyStaffOnShift":true}}}"#))
        stub.on("VenuePairUp", .data(#"{"venues":{"venue":{"pairUp":null}}}"#))
        stub.on("VenuePhotos", .data(#"{"venues":{"venue":{"posts":{"photos":{"nodes":[]}}}}}"#))
        stub.on("VenueSuggestionState", .data(#"{"venues":{"venue":{"id":"\#(ScreenFixtures.venueID)","name":"Nyne","description":null,"reportedClosed":false,"profile":{"website":null,"phone":null}}}}"#))
        stub.tolerate("Lineup", "VenueLineup", "Show", "VenueShow", "Posts", "VenuePosts", "Photos", "VenuePhotos", "ArticlesAbout")
        return stub
    }
}

@MainActor
@Suite("Venue screen", .serialized)
struct VenueScreenTests {
    @Test("Shows the venue, its address, friends, chat and what's coming up")
    func loaded() async throws {
        let stub = VenueEventStubs.venueStub()
        stub.on("Venue", .data(VenueEventStubs.venueResponse()))
        let screen = host(VenueScreen(venueID: ScreenFixtures.venueUUID), model: stub.appModel())
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Alex is here"))
        #expect(screen.contains("Nyne"))
        #expect(screen.contains("Open the chat at Nyne, 1 recent message"))
        #expect(screen.contains("Coming Up"))
        #expect(await screen.waitFor("Bingo Night"))
        #expect(screen.contains("Ping here"))
        #expect(stub.last("Venue")?.string("id")?.lowercased() == ScreenFixtures.venueID)
        stub.expectEverythingStubbed()
    }

    @Test("Shows a spinner while the venue loads")
    func loading() async throws {
        let stub = VenueEventStubs.venueStub()
        stub.on("Venue", .data(VenueEventStubs.venueResponse()))
        stub.delay("Venue", by: .seconds(2))
        let screen = host(VenueScreen(venueID: ScreenFixtures.venueUUID), model: stub.appModel())
        defer { screen.tearDown() }

        await screen.settle(timeout: .milliseconds(300))
        #expect(!screen.contains("Alex is here"))
        #expect(!screen.contains("Something went wrong"))
        #expect(await screen.waitFor("Alex is here"))
        stub.expectEverythingStubbed()
    }

    @Test("A venue the API doesn't have reads as an error with Try Again")
    func notFound() async throws {
        let stub = VenueEventStubs.venueStub()
        stub.on("Venue", .data(#"{"venues":{"venue":null}}"#))
        let screen = host(VenueScreen(venueID: ScreenFixtures.venueUUID), model: stub.appModel())
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Something went wrong"))
        stub.expectEverythingStubbed()
    }

    @Test("Try Again after a failure loads the venue")
    func retry() async throws {
        let stub = VenueEventStubs.venueStub()
        let calls = Counter()
        stub.on("Venue") { _ in
            calls.increment() == 1 ? .offline : .data(VenueEventStubs.venueResponse())
        }
        let screen = host(VenueScreen(venueID: ScreenFixtures.venueUUID), model: stub.appModel())
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Try Again"))
        #expect(screen.activate("Try Again"))
        #expect(await screen.waitFor("Alex is here"))
        #expect(stub.count("Venue") >= 2)
        stub.expectEverythingStubbed()
    }

    @Test("Draws in dark mode at a large accessibility size")
    func darkLargeType() async throws {
        let stub = VenueEventStubs.venueStub()
        stub.on("Venue", .data(VenueEventStubs.venueResponse(events: [])))
        let screen = host(VenueScreen(venueID: ScreenFixtures.venueUUID), model: stub.appModel(),
                          colorScheme: .dark, dynamicType: .accessibility3)
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Alex is here"))
        #expect(screen.contains("No upcoming events."))
        stub.expectEverythingStubbed()
    }
}

@MainActor
@Suite("Event screen", .serialized)
struct EventScreenTests {
    private func stub() -> StubAPI {
        let stub = StubAPI()
        stub.stubSignedInBasics()
        stub.tolerate("Lineup", "VenueLineup", "Show", "VenueShow", "Posts", "EventPosts", "EventPhotos", "ArticlesAbout")
        return stub
    }

    @Test("Shows the event, its venue, host and RSVP buttons")
    func loaded() async throws {
        let stub = stub()
        stub.on("Event", .data(VenueEventStubs.eventResponse(hosts: VenueEventStubs.host)))
        let screen = host(EventScreen(eventID: ScreenFixtures.eventUUID), model: stub.appModel())
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Bingo Night"))
        #expect(screen.contains("Nyne"))
        #expect(await screen.waitFor("Miss Coco"))
        #expect(screen.contains(RSVP.attending.title))
        #expect(screen.contains(RSVP.maybe.title))
        stub.expectEverythingStubbed()
    }

    @Test("Going sends the RSVP and keeps it")
    func rsvp() async throws {
        let stub = stub()
        stub.on("Event", .data(VenueEventStubs.eventResponse()))
        stub.on("RSVPEvent", .data(#"{"rsvpEvent":{"event":{"id":"\#(ScreenFixtures.eventID)","rsvp":{"mine":"ATTENDING"}}}}"#))
        let screen = host(EventScreen(eventID: ScreenFixtures.eventUUID), model: stub.appModel())
        defer { screen.tearDown() }

        #expect(await screen.waitFor(RSVP.attending.title))
        #expect(screen.activate(RSVP.attending.title))
        #expect(await screen.settle(timeout: .seconds(5)) { stub.requests.contains { $0.key.lowercased().contains("rsvp") } })
        #expect(!screen.contains("Couldn't Save RSVP"))
        stub.expectEverythingStubbed()
    }

    @Test("An RSVP the API refuses rolls back and says so")
    func rsvpRollback() async throws {
        let stub = stub()
        stub.on("Event", .data(VenueEventStubs.eventResponse()))
        stub.on("RSVPEvent", .error("RSVPs are closed"))
        let screen = host(EventScreen(eventID: ScreenFixtures.eventUUID), model: stub.appModel())
        defer { screen.tearDown() }

        #expect(await screen.waitFor(RSVP.attending.title))
        #expect(screen.activate(RSVP.attending.title))
        #expect(await screen.waitFor("Couldn't Save RSVP"))
        stub.expectEverythingStubbed()
    }

    @Test("A failed load shows the error")
    func failure() async throws {
        let stub = stub()
        stub.on("Event", .raw(status: 500, body: "{}"))
        let screen = host(EventScreen(eventID: ScreenFixtures.eventUUID), model: stub.appModel())
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Something went wrong"))
        stub.expectEverythingStubbed()
    }

    @Test("Draws in dark mode at a large accessibility size")
    func darkLargeType() async throws {
        let stub = stub()
        stub.on("Event", .data(VenueEventStubs.eventResponse(rsvp: "\"MAYBE\"")))
        let screen = host(EventScreen(eventID: ScreenFixtures.eventUUID), model: stub.appModel(),
                          colorScheme: .dark, dynamicType: .accessibility3)
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Bingo Night"))
        stub.expectEverythingStubbed()
    }
}

/// A thread-safe call counter for stub replies.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    /// Adds one and returns the new count.
    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }

    var count: Int { lock.withLock { value } }
}
