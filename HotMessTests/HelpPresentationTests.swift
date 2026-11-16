//
//  HelpPresentationTests.swift
//  HotMessTests
//

import Foundation
import Testing

@testable import HotMess

@Suite("Get help presentations")
struct HelpPresentationTests {
    @Test("Get help away from a venue is its own sheet, apart from a venue's or an alert's")
    func anywhereIsDistinct() {
        let venue = HelpVenue(id: UUID(), name: "The Test Bar", address: nil)
        let ids = Set([HelpPresentation.anywhere, .venue(venue), .alert(id: "a1")].map(\.id))
        #expect(ids.count == 3)
        #expect(HelpPresentation.anywhere.id == "anywhere")
    }
}
