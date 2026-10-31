//
//  CalendarSyncTests.swift
//  HotMessTests
//

import Foundation
import Testing

@testable import HotMess

@Suite("Calendar sync")
struct CalendarSyncTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Fills the calendar entry from the event, three hours when it has no end")
    func entry() {
        let stud = Venue(id: UUID(), name: "The Stud", address: "1123 Folsom St")
        let event = Event(id: UUID(uuidString: "0A1E0AAC-1D01-42D1-9DE5-F0279842D9C0")!, name: "Drag Bingo",
                          startDate: start, venue: stud)
        let entry = CalendarEntry(event: event)

        #expect(entry.title == "Drag Bingo")
        #expect(entry.end == start.addingTimeInterval(3 * 3600))
        #expect(entry.location == "The Stud, 1123 Folsom St")
        #expect(entry.url?.absoluteString == "https://hotmess.social/events/0a1e0aac-1d01-42d1-9de5-f0279842d9c0")
    }

    @Test("Keeps the event's own end, and no location without a venue")
    func ownEnd() {
        let event = Event(id: UUID(), name: "Late", startDate: start, endDate: start.addingTimeInterval(5 * 3600))
        let entry = CalendarEntry(event: event)

        #expect(entry.end == start.addingTimeInterval(5 * 3600))
        #expect(entry.location == nil)
    }

    @Test("Reads the subscription link and the create payload")
    func decodes() throws {
        #expect(HotMessAPI.Documents.createCalendarFeed.contains("createCalendarFeed(input: { reset: $reset })"))

        let feed = #"{ "url": "https://api.hotmess.social/v1/calendar/abc.ics", "webcalUrl": "webcal://api.hotmess.social/v1/calendar/abc.ics", "googleUrl": "https://calendar.google.com/calendar/render?cid=webcal%3A%2F%2Fapi" }"#
        let me = Data(#"{ "me": { "calendarFeed": \#(feed) } }"#.utf8)
        #expect(try JSONDecoder.hotMess.decode(CalendarFeedResponse.self, from: me).me?.calendarFeed?.webcalUrl.scheme == "webcal")

        let none = Data(#"{ "me": { "calendarFeed": null } }"#.utf8)
        #expect(try JSONDecoder.hotMess.decode(CalendarFeedResponse.self, from: none).me?.calendarFeed == nil)

        let made = Data(#"{ "createCalendarFeed": { "calendarFeed": \#(feed) } }"#.utf8)
        #expect(try JSONDecoder.hotMess.decode(CreateCalendarFeedResponse.self, from: made).createCalendarFeed.calendarFeed.url.pathExtension == "ics")
    }
}
