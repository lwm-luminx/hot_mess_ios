//
//  YourSafetyAlertsScreen.swift
//  HotMess
//

import SwiftUI

/// Me > Your Safety Alerts: the user's alerts that are still open, and those
/// closed in the last day. Each opens its Get help sheet.
struct YourSafetyAlertsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var state: LoadState<[SafetyAlert]> = .loading

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
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle(String(localized: "Your Safety Alerts"))
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: model.helpPresentation) { _, presentation in
            if presentation == nil { Task { await load() } }
        }
    }

    private func load() async {
        do {
            state = .loaded(try await model.api.safetyAlerts())
        } catch {
            state = LoadState(catching: error)
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
