//
//  HotMessLiveActivity.swift
//  HotMessWidgets
//

import ActivityKit
import SwiftUI
import WidgetKit

/// An open Ping or Quickie on the Lock Screen and in the Dynamic Island.
/// Tapping it opens the Ping, or the venue where the Quickie sheet is. Its
/// buttons join a friend's Ping, say yes to the Quickie's topic or ask for a
/// new one (each runs in the app), or open the chat.
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.status)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if let topic = context.state.topic {
                            TopicLine(topic: topic)
                        }
                        ActivityButtons(context: context)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 10) {
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
            if !context.isStale {
                if let topic = context.state.topic {
                    TopicLine(topic: topic)
                        .padding(.leading, 44)
                }
                ActivityButtons(context: context)
                    .padding(.leading, 44)
            }
        }
        .padding(16)
    }
}

/// The Quickie's topic: what the two of them talk about.
private struct TopicLine: View {
    let topic: String

    var body: some View {
        Text("\u{201C}\(topic)\u{201D}")
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The activity's buttons, if it has any. A Quickie's need its pairing.
private struct ActivityButtons: View {
    let context: ActivityViewContext<HotMessActivityAttributes>

    private var actions: [HotMessActivityAttributes.Action] {
        let actions = context.state.actions ?? []
        return context.state.matchID == nil ? actions.filter { $0 == .joinPing || $0 == .chat } : actions
    }

    var body: some View {
        if !actions.isEmpty {
            HStack(spacing: 8) {
                ForEach(actions, id: \.self) { action in
                    button(for: action)
                }
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private func button(for action: HotMessActivityAttributes.Action) -> some View {
        let key = context.attributes.key
        let matchID = context.state.matchID ?? ""
        switch action {
        case .joinPing:
            Button(intent: JoinPingIntent(pingID: key)) {
                Label("I'm in", systemImage: "hand.raised.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(HotMessLiveActivity.accent)
        case .acceptQuickie:
            Button(intent: AcceptQuickieIntent(venueID: key, matchID: matchID)) {
                Label("I'm in", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .tint(HotMessLiveActivity.accent)
        case .newTopic:
            Button(intent: NewQuickieTopicIntent(venueID: key, matchID: matchID)) {
                Label("New topic", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .tint(.white)
        case .chat:
            if let url = context.state.chatURL {
                Link(destination: url) {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(HotMessLiveActivity.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
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
