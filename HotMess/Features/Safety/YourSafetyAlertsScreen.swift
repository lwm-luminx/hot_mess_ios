//
//  YourSafetyAlertsScreen.swift
//  HotMess
//

import SwiftUI

/// Me > Your Safety Alerts: the user's alerts that are still open, and those
/// closed in the last day. Each opens its Get help sheet. Below them, Help
/// history: what they asked for help with and the places shared with them,
/// kept on this phone (``HelpHistory``) with a Clear button.
struct YourSafetyAlertsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var state: LoadState<[SafetyAlert]> = .loading
    @State private var isConfirmingClear = false
    private let history = HelpHistory.shared

    var body: some View {
        LoadStateView(state: state, retry: { Task { await load() } }) { alerts in
            List {
                if alerts.isEmpty {
                    Text("Alerts you send to venue staff show here while they're open, and for a day after.")
                        .font(.hotMess(.body))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(alerts) { alert in
                        Button {
                            model.helpPresentation = .alert(id: alert.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alert.venue.name ?? String(localized: "A venue"))
                                    .font(.hotMess(.body, semibold: true))
                                    .foregroundStyle(.primary)
                                Text("\(Self.status(alert)) · \(alert.createdAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.hotMess(.footnote))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                historySection
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle(String(localized: "Your Safety Alerts"))
        .confirmationDialog(
            String(localized: "Clear your help history?"),
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Clear History"), role: .destructive) { history.clear() }
        } message: {
            Text("This removes every request and shared place from this phone. Open alerts stay open.")
        }
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: model.helpPresentation) { _, presentation in
            if presentation == nil { Task { await load() } }
        }
    }

    private func load() async {
        do {
            let alerts = try await model.api.safetyAlerts()
            history.record(alerts)
            state = .loaded(alerts)
        } catch {
            // Offline, history is still worth showing: that's when it's needed.
            state = history.entries.isEmpty ? LoadState(catching: error) : .loaded([])
        }
    }

    @ViewBuilder private var historySection: some View {
        Section {
            if history.entries.isEmpty {
                Text("Places people share with you when you ask for help are saved here, on this phone only, so you can find them later.")
                    .font(.hotMess(.footnote))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(history.entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(entry.venueName ?? String(localized: "Help request")) · \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.hotMess(.footnote))
                            .foregroundStyle(.secondary)
                        Text(entry.summary)
                            .font(.hotMess(.body))
                        ForEach(entry.resources) { resource in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resource.title)
                                    .font(.hotMess(.body, semibold: true))
                                if let note = resource.intakeNote, !note.isEmpty {
                                    Text(note)
                                        .font(.hotMess(.footnote))
                                        .foregroundStyle(.secondary)
                                }
                                SharedResourceLinks(resource: resource)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                Button(String(localized: "Clear History"), role: .destructive) { isConfirmingClear = true }
                    .accessibilityIdentifier("help.history.clear")
            }
        } header: {
            Text("Help history")
        } footer: {
            Text("Kept on this phone only. Signing out clears it too.")
        }
    }

    static func status(_ alert: SafetyAlert) -> String {
        switch alert.state {
        case .open: String(localized: "Waiting for staff")
        case .acknowledged: String(localized: "\(alert.acknowledgedByName ?? String(localized: "Staff")) is on it")
        case .cancelled: String(localized: "Cancelled")
        case .closed, .unknown: String(localized: "Closed")
        }
    }
}

/// Me > Getting Help at a Venue: what "Get help" does, before anyone needs it.
struct GettingHelpScreen: View {
    var body: some View {
        List {
            Section {
                Text("When the app places you at a venue, its page has a quiet Get help button. Tap it to tell the staff on shift you feel unsafe, without anyone around you knowing.")
                Text("Say where you are and what's going on if you can, or just send it. Someone on shift picks it up and you'll see who's coming. You can message them privately; it's never in venue chat.")
                Text("If nobody picks it up in 2 minutes, the venue's managers hear it too, and the app helps you reach a friend, a ride or support.")
                Text("Only staff see who sent an alert. The other person is never told.")
            }
            .font(.hotMess(.body))

            EmergencySection()
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "Getting Help"))
    }
}

/// Call, text, map and website buttons for a shared place, in the thread and
/// in Help history.
struct SharedResourceLinks: View {
    let resource: SafetyAlert.SharedResource

    var body: some View {
        HStack(spacing: 12) {
            if let url = resource.callURL { Link(String(localized: "Call"), destination: url) }
            if let url = resource.textURL { Link(String(localized: "Text"), destination: url) }
            if let url = resource.mapsURL { Link(String(localized: "Map"), destination: url) }
            if let url = resource.websiteURL { Link(String(localized: "Website"), destination: url) }
        }
        .font(.hotMess(.footnote, semibold: true))
        .buttonStyle(.borderless)
    }
}
