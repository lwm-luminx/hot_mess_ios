//
//  VenueOrderingTests.swift
//  HotMessTests
//

import Foundation
import Testing

@testable import HotMess

@Suite("Venue ordering")
struct VenueOrderingTests {
    private func decode(_ extra: String) throws -> VenueWithEvents? {
        let json = """
        {"venues":{"venue":{"id":"8b4f1b60-9a5d-4d0e-9b3f-2c6b3e5d8a11","name":"Stonewall","distance":null,
         "point":null,"photo_url":null,"banner_url":null,"chat":{"open":false}\(extra)}}}
        """
        return try JSONDecoder.hotMess.decode(VenueResponse.self, from: Data(json.utf8)).venue
    }

    @Test("A venue with an ordering page gets an Order button that opens it")
    func decodesOrderingPage() throws {
        let venue = try decode(#","ordering":{"url":"https://order.toasttab.com/online/stonewall"}"#)
        #expect(venue?.orderingURL == URL(string: "https://order.toasttab.com/online/stonewall"))
    }

    @Test("No ordering mixin, no page, or a page that isn't https means no Order button")
    func noOrderingPage() throws {
        #expect(try decode("")?.orderingURL == nil)
        #expect(try decode(#","ordering":null"#)?.orderingURL == nil)
        #expect(try decode(#","ordering":{"url":null}"#)?.orderingURL == nil)
        #expect(try decode(#","ordering":{"url":"http://example.com/order"}"#)?.orderingURL == nil)
    }
}
