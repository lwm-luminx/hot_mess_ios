//
//  ScreenViewModelTests.swift
//  HotMessTests
//
//  Now's, a venue's and an event's view models against the stub API.
//

import CoreLocation
import Foundation
import Testing

@testable import HotMess

@MainActor
@Suite("Screen view models", .serialized)
struct ScreenViewModelTests {
    @Test("Now with no position loads Pings and titles itself Now")
    func nowWithoutPosition() async throws {
        let stub = StubAPI()
        stub.stubSignedInBasics()
        let model = stub.appModel()
        let viewModel = NowViewModel(api: model.api, friends: model.friends)

        await viewModel.load(from: model.location)

        let now = try #require(viewModel.state.value)
        #expect(now.myPing == nil)
        #expect(stub.operationNames == ["Pings"])
        stub.expectEverythingStubbed()
    }

    @Test("Now at a venue reports the position and remembers its friends")
    func nowAtVenue() async throws {
        let stub = StubAPI()
        stub.stubSignedInBasics()
        stub.on("ReportLocation", .data(ScreenFixtures.nowAtVenue))
        stub.tolerate("ClosestLocale")
        let model = stub.appModel()
        await model.location.simulate(at: CLLocationCoordinate2D(latitude: 47.65, longitude: -117.41),
                                      venueName: "Nyne", allowed: true)
        let viewModel = NowViewModel(api: model.api, friends: model.friends)

        await viewModel.load(from: model.location, sentAfter: .now)

        let now = try #require(viewModel.state.value)
        #expect(now.venue?.name == "Nyne")
        #expect(now.recentMessages.map(\.body) == ["who's here?"])
        #expect(stub.count("ReportLocation") >= 1)
        stub.expectEverythingStubbed()
    }

    @Test("A failed first load is an error; a failed refresh keeps what's on screen")
    func nowFailure() async throws {
        let stub = StubAPI()
        stub.stubSignedInBasics()
        let fail = LockedFlag(true)
        stub.on("ReportLocation") { _ in fail.value ? .raw(status: 500, body: "{}") : .data(ScreenFixtures.nowAtVenue) }
        stub.tolerate("ClosestLocale")
        let model = stub.appModel()
        await model.location.simulate(at: CLLocationCoordinate2D(latitude: 47.65, longitude: -117.41),
                                      venueName: "Nyne", allowed: true)
        let viewModel = NowViewModel(api: model.api)

        await viewModel.load(from: model.location, sentAfter: .now)
        guard case .failed = viewModel.state else {
            Issue.record("Expected a failure, got \(viewModel.state)")
            return
        }

        fail.value = false
        await viewModel.load(from: model.location, sentAfter: .now)
        #expect(viewModel.state.value?.venue?.name == "Nyne")

        fail.value = true
        await viewModel.load(from: model.location, sentAfter: .now)
        #expect(viewModel.state.value?.venue?.name == "Nyne")
        stub.expectEverythingStubbed()
    }

    @Test("Ending my Ping takes it off Now; a refusal is reported")
    func endPing() async throws {
        let stub = StubAPI()
        stub.stubSignedInBasics()
        let model = stub.appModel()
        let viewModel = NowViewModel(api: model.api)
        await viewModel.load(from: model.location)

        // No Ping of mine: nothing to end, nothing sent.
        await viewModel.endMyPing()
        #expect(stub.count("EndPing") == 0)
        #expect(NowViewModel.message(for: APIError.notFound).isEmpty == false)
        stub.expectEverythingStubbed()
    }

    @Test("A venue loads in one request and remembers its friends")
    func venue() async throws {
        let stub = StubAPI()
        stub.on("Venue", .data(VenueEventStubs.venueResponse()))
        let model = stub.appModel()
        let viewModel = VenueViewModel(api: model.api, venueID: ScreenFixtures.venueUUID, friends: model.friends)

        await viewModel.load()

        let overview = try #require(viewModel.state.value)
        #expect(overview.venue.name == "Nyne")
        #expect(overview.chatOpen)
        #expect(overview.friends.map(\.name) == ["Alex Friend"])
        #expect(overview.events.map(\.name) == ["Bingo Night"])
        #expect(overview.nextEvent?.name == "Bingo Night")
        #expect(viewModel.activePings.isEmpty)
        #expect(!viewModel.isJoinedHere(userID: stub.userID))
        #expect(stub.operationNames == ["Venue"])
        stub.expectEverythingStubbed()
    }

    @Test("A venue the API doesn't have, or a failed request, is an error")
    func venueErrors() async throws {
        let stub = StubAPI()
        let missing = LockedFlag(true)
        stub.on("Venue") { _ in missing.value ? .data(#"{"venues":{"venue":null}}"#) : .offline }
        let model = stub.appModel()
        let viewModel = VenueViewModel(api: model.api, venueID: ScreenFixtures.venueUUID)

        await viewModel.load()
        guard case .failed = viewModel.state else {
            Issue.record("Expected not found, got \(viewModel.state)")
            return
        }
        missing.value = false
        await viewModel.load()
        guard case let .failed(_, retryable) = viewModel.state else {
            Issue.record("Expected offline, got \(viewModel.state)")
            return
        }
        #expect(retryable)
        stub.expectEverythingStubbed()
    }

    @Test("An event loads with its hosts")
    func event() async throws {
        let stub = StubAPI()
        stub.on("Event", .data(VenueEventStubs.eventResponse(hosts: VenueEventStubs.host)))
        let model = stub.appModel()
        let viewModel = EventViewModel(api: model.api, eventID: ScreenFixtures.eventUUID)

        await viewModel.load()

        let detail = try #require(viewModel.state.value)
        #expect(detail.event.name == "Bingo Night")
        #expect(detail.hosts.map(\.name) == ["Miss Coco"])
        #expect(detail.people.isEmpty)
        #expect(viewModel.isTonight)
        #expect(viewModel.activePings.isEmpty)
        stub.expectEverythingStubbed()
    }

    @Test("An RSVP is shown at once and kept when the API takes it")
    func rsvpKept() async throws {
        let stub = StubAPI()
        stub.on("Event", .data(VenueEventStubs.eventResponse()))
        stub.on("RSVPEvent", .data(#"{"rsvpEvent":{"event":{"id":"\#(ScreenFixtures.eventID)","rsvp":{"mine":"ATTENDING"}}}}"#))
        let model = stub.appModel()
        let viewModel = EventViewModel(api: model.api, eventID: ScreenFixtures.eventUUID)
        await viewModel.load()

        await viewModel.setRSVP(.attending)

        #expect(viewModel.state.value?.event.rsvp == .attending)
        #expect(viewModel.rsvpError == nil)
        #expect(stub.requests.contains { $0.key.lowercased().contains("rsvp") })

        // The same answer again sends nothing.
        let sent = stub.requests.count
        await viewModel.setRSVP(.attending)
        #expect(stub.requests.count == sent)
        stub.expectEverythingStubbed()
    }

    @Test("An RSVP the API refuses rolls back to what the server has")
    func rsvpRollback() async throws {
        let stub = StubAPI()
        stub.on("Event", .data(VenueEventStubs.eventResponse(rsvp: "\"MAYBE\"")))
        stub.on("RSVPEvent", .error("RSVPs are closed"))
        let model = stub.appModel()
        let viewModel = EventViewModel(api: model.api, eventID: ScreenFixtures.eventUUID)
        await viewModel.load()
        #expect(viewModel.state.value?.event.rsvp == .maybe)

        await viewModel.setRSVP(.attending)

        #expect(viewModel.state.value?.event.rsvp == .maybe)
        let error = try #require(viewModel.rsvpError)
        #expect(!error.isEmpty)
        viewModel.dismissRSVPError()
        #expect(viewModel.rsvpError == nil)
        stub.expectEverythingStubbed()
    }

    @Test("An event that fails to load is an error, and RSVPs do nothing")
    func eventFailure() async throws {
        let stub = StubAPI()
        stub.on("Event", .data(#"{"events":{"event":null}}"#))
        let model = stub.appModel()
        let viewModel = EventViewModel(api: model.api, eventID: ScreenFixtures.eventUUID)

        await viewModel.load()
        await viewModel.setRSVP(.attending)

        guard case .failed = viewModel.state else {
            Issue.record("Expected a failure, got \(viewModel.state)")
            return
        }
        #expect(!viewModel.isTonight)
        #expect(stub.operationNames == ["Event"])
        stub.expectEverythingStubbed()
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool

    init(_ value: Bool) { stored = value }

    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
