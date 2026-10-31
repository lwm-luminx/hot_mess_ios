//
//  CalendarSyncScreen.swift
//  HotMess
//

import SwiftUI
import UIKit

/// Me > Calendar: subscribes the user's calendar to the events they're going
/// to (and might go to), so RSVPs, time changes and cancellations show up in
/// Calendar on their own. The link is private; Reset Link ends the old one.
struct CalendarSyncScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    @State private var feed: CalendarFeed?
    @State private var isWorking = false
    @State private var error: String?
    @State private var isConfirmingReset = false
    @State private var didCopy = false

    var body: some View {
        List {
            Section {
                Button {
                    Task { await subscribe() }
                } label: {
                    Label(String(localized: "Subscribe in Calendar"), systemImage: "calendar.badge.plus")
                }
                .disabled(isWorking)
                .accessibilityIdentifier("calendar.subscribe")

                Button {
                    Task { await withFeed { feed in openURL(feed.googleUrl) } }
                } label: {
                    Label(String(localized: "Add to Google Calendar"), systemImage: "globe")
                }
                .disabled(isWorking)
                .accessibilityIdentifier("calendar.google")
            } footer: {
                Text("Events you're going to, and ones you might go to, stay up to date in your calendar. It checks for changes every hour or so.")
            }

            if let feed {
                Section {
                    Button {
                        UIPasteboard.general.url = feed.url
                        didCopy = true
                    } label: {
                        Label(didCopy ? String(localized: "Copied") : String(localized: "Copy Link"), systemImage: "link")
                    }
                    .accessibilityIdentifier("calendar.copy")

                    Button(role: .destructive) {
                        isConfirmingReset = true
                    } label: {
                        Label(String(localized: "Reset Link"), systemImage: "arrow.clockwise")
                    }
                    .disabled(isWorking)
                    .accessibilityIdentifier("calendar.reset")
                } footer: {
                    Text("Anyone with the link can see these events. If you shared it by mistake, reset it and subscribe again.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "Calendar"))
        .task { feed = try? await model.api.calendarFeed() }
        .confirmationDialog(
            String(localized: "Reset your calendar link?"),
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Reset Link"), role: .destructive) {
                Task { await reset() }
            }
        } message: {
            Text("Calendars subscribed to the old link stop updating.")
        }
        .alert(
            String(localized: "Couldn't set up calendar sync"),
            isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func subscribe() async {
        await withFeed { feed in openURL(feed.webcalUrl) }
    }

    /// Runs `action` with the user's link, making it first if they have none.
    private func withFeed(_ action: (CalendarFeed) -> Void) async {
        if let feed {
            action(feed)
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let made = try await model.api.createCalendarFeed()
            feed = made
            action(made)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reset() async {
        isWorking = true
        defer { isWorking = false }
        do {
            feed = try await model.api.createCalendarFeed(reset: true)
            didCopy = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}
