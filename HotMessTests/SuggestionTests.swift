//
//  SuggestionTests.swift
//  HotMessTests
//

import AudienceKit
import Foundation
import Testing

@testable import HotMess

struct SuggestionTests {
    @Test func sendsOnlyWhatItProposes() {
        var request = SuggestionRequest(kind: .correction, targetID: "venue-1", body: "  New number  ")
        request.proposed["phone"] = .string("206-555-0100")
        request.evidence = [SuggestionEvidence(url: "https://example.com")]

        guard case let .object(input)? = request.variables["input"] else {
            Issue.record("No input")
            return
        }
        #expect(input["kind"] == .string("CORRECTION"))
        #expect(input["targetId"] == .string("venue-1"))
        #expect(input["body"] == .string("New number"))
        #expect(input["proposed"] == .object(["phone": .string("206-555-0100")]))
        #expect(input["evidence"] == .array([.object(["kind": .string("link"), "url": .string("https://example.com")])]))
        // Left out unless set, so the request works against an API without it.
        #expect(input["notListed"] == nil)
        #expect(input["localeId"] == nil)
    }

    @Test func saysItIsADifferentPlaceWhenAsked() {
        let request = SuggestionRequest(kind: .missingVenue, notListed: true)
        guard case let .object(input)? = request.variables["input"] else {
            Issue.record("No input")
            return
        }
        #expect(input["notListed"] == .bool(true))
        #expect(input["targetId"] == nil)
    }

    @Test func decodesYourSuggestionsWithTheirBadges() throws {
        let json = """
        {"me":{"submissions":[
          {"id":"s1","kind":"MISSING_VENUE","status":"APPROVED","reporterCount":1,"proposed":{"name":"Neighbours"},
           "createdAt":"2026-10-20T05:00:00Z","venue":{"id":"6f1c2c1e-4d2a-4f6b-9a37-0c1d2e3f4a5b","name":"Neighbours"},
           "event":null,"decisions":[{"action":"APPROVE","reason":null}]},
          {"id":"s2","kind":"CORRECTION","status":"REJECTED","reporterCount":2,"proposed":{"phone":"1"},
           "createdAt":"2026-10-20T05:00:00Z","venue":{"id":"v","name":"The Wildrose"},"event":null,
           "decisions":[{"action":"REJECT","reason":"The venue's site still shows the old number"}]},
          {"id":"s3","kind":"MISSING_EVENT","status":"NEEDS_VENUE","reporterCount":1,"proposed":{"name":"Drag Bingo"},
           "createdAt":"2026-10-20T05:00:00Z","venue":{"id":"v","name":"The Wildrose"},"event":null,"decisions":[]},
          {"id":"s4","kind":"SOMETHING_NEW","status":"LATER","reporterCount":1,"proposed":{},
           "createdAt":"2026-10-20T05:00:00Z","venue":null,"event":null,"decisions":[]}
        ]}}
        """
        let suggestions = try JSONDecoder.hotMess.decode(MySuggestionsResponse.self, from: Data(json.utf8)).me?.submissions ?? []

        #expect(suggestions.map(\.badge) == ["Added", "Not changed", "Being checked", "Being checked"])
        #expect(suggestions.map(\.title) == ["Neighbours", "The Wildrose", "Drag Bingo", "Fix"])
        #expect(suggestions[0].addedRoute == .venue(UUID(uuidString: "6f1c2c1e-4d2a-4f6b-9a37-0c1d2e3f4a5b")!))
        #expect(suggestions[1].rejectionReason == "The venue's site still shows the old number")
        #expect(suggestions[2].addedRoute == nil)
    }

    @Test func readsAnExistingListingInsteadOfASuggestion() throws {
        let json = """
        {"submitContribution":{"merged":false,"submission":null,
          "existingVenue":{"id":"6f1c2c1e-4d2a-4f6b-9a37-0c1d2e3f4a5b","name":"The Wildrose"},"existingEvent":null}}
        """
        let payload = try JSONDecoder.hotMess.decode(SubmitContributionResponse.self, from: Data(json.utf8)).submitContribution
        #expect(payload.submission == nil)
        #expect(payload.existingVenue?.name == "The Wildrose")
    }
}
