//
//  AboutUpdateRows.swift
//  HotMess
//

import AudienceKit
import AudienceKitUI
import SwiftUI

/// The update rows in Me › About (design: TestFlightUpdates.md, "About this
/// app"): where the build came from, whether a newer one is waiting, when we
/// last looked, "Check for updates" and "Open in TestFlight" / "Open on the
/// App Store". Development builds (run from Xcode) show none of them.
struct AboutUpdateRows: View {
    @ObservedObject var updates: AudienceUpdates
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let source = updates.installSource, source.isUpdatable {
            if updates.pendingUpdate != nil {
                AudienceUpdateBanner(updates: updates)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .listRowBackground(Color.clear)
            }

            if let installedFrom = UpdateText.installedFrom(source) {
                LabeledContent(String(localized: "Installed from")) {
                    if source == .testFlight {
                        Text(installedFrom)
                            .font(.hotMess(.caption, semibold: true))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .foregroundStyle(Color.hotMessAccent)
                            .background(Color.hotMessAccent.opacity(0.12), in: Capsule())
                    } else {
                        Text(installedFrom).foregroundStyle(.secondary)
                    }
                }
            }

            if let status = UpdateText.status(updates.status) {
                LabeledContent(UpdateText.updatesRowTitle(source)) {
                    Label(status, systemImage: updates.availableUpdate == nil ? "checkmark.circle" : "arrow.up.circle")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(updates.availableUpdate == nil ? Color.green : Color.blue)
                        .monospacedDigit()
                }
            }

            InfoRow(
                title: String(localized: "Last checked"),
                value: updates.lastChecked.map { Self.lastChecked($0) } ?? String(localized: "Not yet")
            )

            Button {
                Task { await updates.checkNow() }
            } label: {
                HStack {
                    Text("Check for updates")
                    Spacer()
                    if updates.isChecking {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise").accessibilityHidden(true)
                    }
                }
            }
            .disabled(updates.isChecking)
            .accessibilityIdentifier("me.checkForUpdates")

            if updates.release != nil {
                Button {
                    Task { await updates.openUpdate() }
                } label: {
                    HStack {
                        Text(source == .testFlight
                            ? String(localized: "Open in TestFlight")
                            : String(localized: "Open on the App Store"))
                        Spacer()
                        Image(systemName: "arrow.up.forward.square").accessibilityHidden(true)
                    }
                }
            }
        }
    }

    /// How often we look, under the About section.
    static func footnote(for source: InstallSource?) -> String? {
        switch source {
        case .testFlight:
            String(localized: "We check for a new beta when you open Hot Mess, at most once a day.")
        case .appStore:
            String(localized: "We check for updates when you open Hot Mess, at most once a day.")
        default:
            nil
        }
    }

    /// "Mon 9:14pm" within the last week, "Oct 12" before that.
    static func lastChecked(_ date: Date, now: Date = Date(), calendar: Calendar = .current,
                            locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if (0 ..< 7).contains(days) {
            formatter.setLocalizedDateFormatFromTemplate("EEEjmm")
            formatter.amSymbol = "am"
            formatter.pmSymbol = "pm"
            return formatter.string(from: date)
                .replacingOccurrences(of: " am", with: "am")
                .replacingOccurrences(of: " pm", with: "pm")
                .replacingOccurrences(of: "\u{202F}am", with: "am")
                .replacingOccurrences(of: "\u{202F}pm", with: "pm")
        }
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }
}

/// "We check for a new beta when you open Hot Mess, at most once a day."
struct AboutUpdateFootnote: View {
    @ObservedObject var updates: AudienceUpdates

    var body: some View {
        if let text = AboutUpdateRows.footnote(for: updates.installSource) {
            Text(text)
        }
    }
}
