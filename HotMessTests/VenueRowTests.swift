//
//  VenueRowTests.swift
//  HotMessTests
//

import Foundation
import Testing

@testable import HotMess

@Suite("Venue rows")
struct VenueRowTests {
    let eagle = Venue(id: UUID(), name: "The Eagle")
    let rumors = Venue(id: UUID(), name: "Rumors")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Keeps each venue's soonest event that isn't over")
    func nextEvents() {
        let over = Event(id: UUID(), name: "Brunch", startDate: now.addingTimeInterval(-6 * 3600),
                         endDate: now.addingTimeInterval(-3600), venue: eagle)
        let later = Event(id: UUID(), name: "Bear Night", startDate: now.addingTimeInterval(3 * 3600), venue: eagle)
        let sooner = Event(id: UUID(), name: "Happy Hour", startDate: now.addingTimeInterval(3600), venue: eagle)
        let bingo = Event(id: UUID(), name: "Drag Bingo", startDate: now.addingTimeInterval(7200), venue: rumors)

        let next = VenuesViewModel.nextEvents([over, later, sooner, bingo], at: now)

        #expect(next[eagle.id]?.id == sooner.id)
        #expect(next[rumors.id]?.id == bingo.id)
    }

    @Test("Says until when an event is on")
    func onNowLine() {
        let event = Event(id: UUID(), name: "Bear Night", startDate: now.addingTimeInterval(-3600),
                          endDate: now.addingTimeInterval(3600), venue: eagle)

        #expect(event.isOn(at: now))
        #expect(event.venueRowLine(at: now).hasPrefix("Bear Night · until "))
    }

    @Test("Uses the next-up line before it starts")
    func nextUpLine() {
        let event = Event(id: UUID(), name: "Drag Bingo", startDate: now.addingTimeInterval(3600), venue: rumors)

        #expect(!event.isOn(at: now))
        #expect(event.venueRowLine(at: now) == event.nextUpLine)
    }
}
