//
//  PairUpScreenTests.swift
//  HotMessTests
//
//  Quickie (Pair me up): the model against the stub API, and the sheet hosted
//  in a window through each state of a pairing.
//

import Foundation
import SwiftUI
import Testing

@testable import HotMess

enum PairUpStubs {
    static let matchID = "5e4d3c2b-1a09-4f8e-9d7c-6b5a4f3e2d1c"

    static func match(accepted: Bool = false, partnerAccepted: Bool = false, metAt: String = "null",
                      shared: Bool = false, partnerShared: Bool = false) -> String {
        """
        {"id":"\(matchID)","accepted":\(accepted),"partnerAccepted":\(partnerAccepted),"shared":\(shared),
         "partnerShared":\(partnerShared),"bonus":false,"metAt":\(metAt),"endReason":null,
         "topic":{"key":"karaoke","text":"Worst song you'd still sing"},
         "partner":{"id":"0a1b2c3d-4e5f-4061-8a7b-9c0d1e2f3a4b","name":"Jamie","avatarUrl":null,"lookFor":"Green hat"}}
        """
    }

    static func state(_ status: String, match: String = "null", metCount: Int = 0) -> String {
        #"{"status":"\#(status)","lookFor":"Red jacket","metCount":\#(metCount),"match":\#(match),"bonus":null}"#
    }

    static func venue(here: Bool, mine: String = "null") -> String {
        #"{"venues":{"venue":{"pairUp":{"here":\#(here),"mine":\#(mine)}}}}"#
    }

    static func mutation(_ name: String, _ state: String) -> String {
        #"{"\#(name)":{"pairUp":\#(state)}}"#
    }

    static func stub(venue: String) -> StubAPI {
        let stub = StubAPI()
        stub.stubSignedInBasics()
        stub.on("VenuePairUp", .data(venue))
        return stub
    }
}

@MainActor
@Suite("Quickie model", .serialized)
struct PairUpModelTests {
    @Test("Loads whether the user is here and their pairing")
    func load() async throws {
        let stub = PairUpStubs.stub(venue: PairUpStubs.venue(here: true))
        let model = PairUpModel(api: stub.appModel().api, venueID: ScreenFixtures.venueUUID)

        await model.load()

        #expect(model.isLoaded)
        #expect(model.isHere)
        #expect(model.state == nil)
        #expect(stub.last("VenuePairUp")?.string("id")?.lowercased() == ScreenFixtures.venueID)
        stub.expectEverythingStubbed()
    }

    @Test("Joining searches, accepting waits, and a scan that meets celebrates once")
    func flow() async throws {
        let stub = PairUpStubs.stub(venue: PairUpStubs.venue(here: true))
        stub.on("JoinPairUp", .data(PairUpStubs.mutation("joinPairUp", PairUpStubs.state("SEARCHING"))))
        stub.on("AcceptPairUp", .data(PairUpStubs.mutation("acceptPairUp",
                                                           PairUpStubs.state("WAITING", match: PairUpStubs.match(accepted: true)))))
        stub.on("ShowPairUpCode", .data(#"{"showPairUpCode":{"code":"HM-1234"}}"#))
        stub.on("ScanPairUpCode", .data(#"{"scanPairUpCode":{"outcome":"MET","match":\#(PairUpStubs.match(accepted: true, partnerAccepted: true, metAt: "\"2026-11-14T22:00:00Z\"")),"pairUp":\#(PairUpStubs.state("MET", match: PairUpStubs.match(accepted: true, partnerAccepted: true, metAt: "\"2026-11-14T22:00:00Z\""), metCount: 1))}}"#))
        stub.on("SharePairUp", .data(PairUpStubs.mutation("sharePairUp", PairUpStubs.state("MET", match: PairUpStubs.match(metAt: "\"2026-11-14T22:00:00Z\"", shared: true), metCount: 1))))
        stub.on("LeavePairUp", .data(PairUpStubs.mutation("leavePairUp", PairUpStubs.state("LEFT"))))
        let model = PairUpModel(api: stub.appModel().api, venueID: ScreenFixtures.venueUUID)
        await model.load()

        await model.join(lookFor: "Red jacket")
        #expect(model.state?.status == .searching)
        #expect(stub.last("JoinPairUp")?.string("lookFor") == "Red jacket")

        // Nothing to accept until there's a match.
        await model.accept()
        #expect(stub.count("AcceptPairUp") == 0)

        stub.on("JoinPairUp", .data(PairUpStubs.mutation("joinPairUp", PairUpStubs.state("PROPOSED", match: PairUpStubs.match()))))
        await model.join(lookFor: nil)
        #expect(model.state?.status == .proposed)
        await model.accept()
        #expect(model.state?.status == .waiting)
        #expect(model.state?.match?.accepted == true)

        #expect(await model.code() == "HM-1234")

        await model.scan("HM-9999")
        #expect(model.state?.status == .met)
        #expect(model.scanNotice == nil)
        #expect(model.celebratedMatchID == UUID(uuidString: PairUpStubs.matchID))
        model.dismissCelebration()
        #expect(model.celebratedMatchID == nil)

        await model.share()
        #expect(model.state?.match?.shared == true)

        await model.leave()
        #expect(model.state?.status == .left)
        stub.expectEverythingStubbed()
    }

    @Test("Each scan outcome that isn't a meeting says what to do next")
    func scanNotices() {
        #expect(PairUpModel.notice(for: .met) == nil)
        for outcome in [PairUpScan.Outcome.different, .used, .ended, .own, .unreadable] {
            #expect(PairUpModel.notice(for: outcome)?.isEmpty == false)
        }
    }

    @Test("A refusal is worded for the user, and terms not agreed asks for them")
    func refusals() async throws {
        let stub = PairUpStubs.stub(venue: PairUpStubs.venue(here: true))
        stub.on("JoinPairUp", .error("Quickie is closed tonight"))
        let model = PairUpModel(api: stub.appModel().api, venueID: ScreenFixtures.venueUUID)
        await model.load()

        await model.join(lookFor: nil)

        #expect(model.errorMessage?.isEmpty == false)
        #expect(model.isBusy == false)
        // The refusal reloads the state.
        #expect(stub.count("VenuePairUp") == 2)
        stub.expectEverythingStubbed()
    }

    @Test("A first load that fails says why; a later one keeps quiet")
    func loadFailure() async throws {
        let stub = PairUpStubs.stub(venue: PairUpStubs.venue(here: true))
        stub.on("VenuePairUp", .offline)
        let model = PairUpModel(api: stub.appModel().api, venueID: ScreenFixtures.venueUUID)

        await model.load()
        #expect(model.isLoaded)
        #expect(model.errorMessage != nil)

        model.errorMessage = nil
        await model.load()
        #expect(model.errorMessage == nil)
        stub.expectEverythingStubbed()
    }
}

@MainActor
@Suite("Quickie sheet", .serialized)
struct PairUpSheetTests {
    private func show(_ stub: StubAPI, colorScheme: ColorScheme = .light) async -> (ScreenHost, PairUpModel) {
        let appModel = stub.appModel()
        let model = PairUpModel(api: appModel.api, venueID: ScreenFixtures.venueUUID)
        await model.load()
        let screen = host(PairUpSheet(model: model, venueName: "Nyne"), model: appModel, colorScheme: colorScheme)
        return (screen, model)
    }

    @Test("Away from the venue, it says Quickie opens once you're there")
    func notHere() async throws {
        let stub = PairUpStubs.stub(venue: PairUpStubs.venue(here: false))
        let (screen, _) = await show(stub)
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Quickie opens once you're at Nyne."))
        #expect(screen.contains("Meet someone at Nyne"))
        stub.expectEverythingStubbed()
    }

    @Test("At the venue, Start a quickie joins and shows the search")
    func start() async throws {
        let stub = PairUpStubs.stub(venue: PairUpStubs.venue(here: true))
        stub.on("JoinPairUp", .data(PairUpStubs.mutation("joinPairUp", PairUpStubs.state("SEARCHING"))))
        let (screen, model) = await show(stub)
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Start a quickie"))
        #expect(screen.activate("Start a quickie", exact: false))
        #expect(await screen.settle(timeout: .seconds(5)) { model.state?.status == .searching })
        stub.on("VenuePairUp", .data(PairUpStubs.venue(here: true, mine: PairUpStubs.state("SEARCHING"))))
        #expect(await screen.waitFor("Finding someone to chat with"))
        #expect(screen.contains("Leave Quickie"))
        stub.expectEverythingStubbed()
    }

    @Test("A proposed match asks to say yes, with a topic")
    func proposed() async throws {
        let stub = PairUpStubs.stub(venue: PairUpStubs.venue(here: true, mine: PairUpStubs.state("PROPOSED", match: PairUpStubs.match(partnerAccepted: true))))
        let (screen, _) = await show(stub)
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Yes, let's chat"))
        #expect(screen.contains("They're in. Say yes to see who to look for."))
        #expect(screen.contains("Worst song you'd still sing"))
        #expect(screen.contains("New topic"))
        #expect(screen.contains("Someone else"))
        stub.expectEverythingStubbed()
    }

    @Test("Once both say yes, it shows who to look for and how to scan")
    func revealed() async throws {
        let stub = PairUpStubs.stub(venue: PairUpStubs.venue(here: true, mine: PairUpStubs.state(
            "REVEALED", match: PairUpStubs.match(accepted: true, partnerAccepted: true))))
        stub.on("ShowPairUpCode", .data(#"{"showPairUpCode":{"code":"HM-1234"}}"#))
        let (screen, _) = await show(stub, colorScheme: .dark)
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Look for Jamie"))
        #expect(screen.contains("Green hat"))
        #expect(screen.contains("Scan theirs"))
        stub.expectEverythingStubbed()
    }

    @Test("After meeting, it offers to go again or share in the chat")
    func met() async throws {
        let stub = PairUpStubs.stub(venue: PairUpStubs.venue(here: true, mine: PairUpStubs.state(
            "MET", match: PairUpStubs.match(accepted: true, partnerAccepted: true, metAt: "\"2026-11-14T22:00:00Z\"",
                                            partnerShared: true), metCount: 2)))
        let (screen, _) = await show(stub)
        defer { screen.tearDown() }

        #expect(await screen.waitFor("Let's go again"))
        #expect(screen.contains("Hope you and Jamie had a good chat."))
        #expect(screen.contains("Share in the venue chat"))
        #expect(screen.contains("I'm done"))
        stub.expectEverythingStubbed()
    }
}
