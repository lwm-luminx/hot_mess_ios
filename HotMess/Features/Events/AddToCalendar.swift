//
//  AddToCalendar.swift
//  HotMess
//

import EventKit
import EventKitUI
import SwiftUI

/// What "Add to Calendar" puts in the user's calendar for an event: its
/// name, times, venue and link. A copy: later changes don't follow it (the
/// calendar subscription in Me does).
struct CalendarEntry: Equatable, Identifiable, Sendable {
    /// How long an event with no end runs, as the API's calendar feed does.
    static let defaultLength: TimeInterval = 3 * 60 * 60

    let id: UUID
    let title: String
    let start: Date
    let end: Date
    let location: String?
    let url: URL?

    init(event: Event) {
        id = event.id
        title = event.name
        start = event.startDate
        if let endDate = event.endDate, endDate > event.startDate {
            end = endDate
        } else {
            end = event.startDate.addingTimeInterval(Self.defaultLength)
        }
        location = event.venue.map { venue in
            [venue.name, venue.address].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ")
        }
        url = URL(string: "https://hotmess.social/events/\(event.id.uuidString.lowercased())")
    }
}

/// The system's new-event editor, filled in from `entry`. On iOS 17 and
/// later it runs out of process, so the app needs no calendar access: the
/// user picks the calendar and saves it themselves.
struct AddToCalendarSheet: UIViewControllerRepresentable {
    let entry: CalendarEntry
    /// Called once the user saves or cancels.
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = entry.title
        event.startDate = entry.start
        event.endDate = entry.end
        event.location = entry.location
        event.url = entry.url

        let editor = EKEventEditViewController()
        editor.eventStore = store
        editor.event = event
        editor.editViewDelegate = context.coordinator
        return editor
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onFinish()
        }
    }
}
