//
//  HotMessLiveActivity.swift
//  HotMessWidgets
//

import ActivityKit
import SwiftUI
import WidgetKit

/// An open Ping or Quickie on the Lock Screen and in the Dynamic Island.
/// Tapping it opens the Ping, or the venue where the Quickie sheet is.
struct HotMessLiveActivity: Widget {
    /// Hot Mess pink, so the card reads as the app's at a glance.
    static let accent = Color(red: 1.0, green: 0.27, blue: 0.58)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HotMessActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.attributes.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.kind.symbol)
                        .font(.title2)
                        .foregroundStyle(Self.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let endsAt = context.state.endsAt, endsAt > .now {
                        Text(timerInterval: Date.now...endsAt, countsDown: true)
                            .font(.caption.monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 64)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: context.attributes.kind.symbol)
                    .foregroundStyle(Self.accent)
            } compactTrailing: {
                Text(context.state.short)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            } minimal: {
                Image(systemName: context.attributes.kind.symbol)
                    .foregroundStyle(Self.accent)
            }
            .widgetURL(context.attributes.url)
            .keylineTint(Self.accent)
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<HotMessActivityAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: context.attributes.kind.symbol)
                .font(.title2)
                .foregroundStyle(HotMessLiveActivity.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(context.isStale ? String(localized: "Open Hot Mess to see what's new") : context.state.status)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let endsAt = context.state.endsAt, endsAt > .now {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Ends in")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(timerInterval: Date.now...endsAt, countsDown: true)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 64)
                }
            }
        }
        .padding(16)
    }
}

private extension HotMessActivityAttributes.Kind {
    var symbol: String {
        switch self {
        case .ping: "hand.wave.fill"
        case .quickie: "person.2.wave.2.fill"
        }
    }
}
