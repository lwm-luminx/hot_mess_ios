//
//  ChatPeek.swift
//  HotMess
//

import SwiftUI

/// A read-only glimpse of a chat room (design system "ChatPeek"): the last few
/// messages as the room's own bubbles, with no message box. The whole panel is
/// one button that opens the room. It holds no connection itself: the screen
/// showing it either refreshes `messages` when it loads or follows the room
/// (`LiveChatPeek`) and says so with `isLive`, which turns a spectrum ring
/// around the panel.
struct ChatPeek: View {
    struct Participant: Identifiable {
        let id: String
        let name: String
        let avatarURL: URL?
        var presence: PresenceState? = nil
        var isPlace = false
    }

    /// What tapping the panel does.
    enum Destination {
        case route(AppRoute)
        case action(() -> Void)
    }

    /// "Chat" on a venue, "Small talk" on Now.
    let title: String
    /// The room's name, for VoiceOver: "Open the chat at {roomName}".
    let roomName: String
    /// Oldest first. Only the last `limit` show.
    let messages: [ChatThreadMessage]
    /// People in the room now, when known. Draws "N here now".
    var online: Int?
    var limit: Int
    var participants: [Participant]
    /// The messages are live: the screen is following the room right now.
    var isLive: Bool
    let destination: Destination

    @Environment(\.displayScale) private var displayScale
    @State private var width: CGFloat = 0

    init(
        title: String,
        roomName: String,
        messages: [ChatThreadMessage],
        online: Int? = nil,
        limit: Int = 3,
        participants: [Participant] = [],
        isLive: Bool = false,
        route: AppRoute
    ) {
        self.title = title
        self.roomName = roomName
        self.messages = messages
        self.online = online
        self.limit = limit
        self.participants = participants
        self.isLive = isLive
        self.destination = .route(route)
    }

    init(
        title: String,
        roomName: String,
        messages: [ChatThreadMessage],
        online: Int? = nil,
        limit: Int = 3,
        participants: [Participant] = [],
        isLive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.roomName = roomName
        self.messages = messages
        self.online = online
        self.limit = limit
        self.participants = participants
        self.isLive = isLive
        self.destination = .action(action)
    }

    var body: some View {
        Group {
            switch destination {
            case let .route(route):
                NavigationLink(value: route) { panel }
            case let .action(action):
                Button(action: action) { panel }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat.peek")
    }

    private var visible: [ChatThreadMessage] {
        Array(messages.suffix(max(0, limit)))
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if !participants.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(participants) { participant in
                            Avatar(
                                url: participant.avatarURL,
                                initials: participant.name.initialsForDisplay,
                                size: 32,
                                presence: participant.presence,
                                presenceRing: .hotMessSurfaceSunken,
                                isPlace: participant.isPlace
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }

            if visible.isEmpty {
                Text("No one's said anything yet. Say hello.")
                    .font(.hotMess(.subheadline))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(ChatThreadRow.rows(for: visible)) { row in
                        ChatPeekRow(row: row, maxBubbleWidth: maxBubbleWidth)
                    }
                }
            }

            HStack(spacing: 4) {
                Text(visible.isEmpty ? String(localized: "Start the chat") : String(localized: "Join the chat"))
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
            .font(.hotMess(.subheadline, semibold: true))
            .foregroundStyle(Color.hotMessAccent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hotMessSurfaceSunken, in: .rect(cornerRadius: CardMetrics.cornerRadius))
        // Light `surface-sunken` is all but the wash's colour; the edge makes it a window.
        .overlay {
            RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
                .strokeBorder(Color.hotMessBorder, lineWidth: 1 / displayScale)
        }
        .overlay {
            if isLive {
                LiveRing(cornerRadius: CardMetrics.cornerRadius)
                    .transition(.opacity)
            }
        }
        .animation(HotMessMotion.quick, value: isLive)
        .contentShape(.rect(cornerRadius: CardMetrics.cornerRadius))
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { newValue in
            width = newValue
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(participants.map { participant in
            if let presence = participant.presence, presence != .offline {
                return participant.name + ", " + (presence == .online
                    ? String(localized: "In chat") : String(localized: "Reachable by notification"))
            }
            return participant.name
        }.joined(separator: "; "))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.hotMess(.subheadline, semibold: true))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            if let online, online > 0 {
                HStack(spacing: 6) {
                    PresenceDot(state: .online, size: 8, ringColor: .hotMessSurfaceSunken)
                    Text("\(online) here now")
                        .monospacedDigit()
                }
                .font(.hotMess(.footnote))
                .foregroundStyle(.secondary)
            } else if isLive {
                // The ring never says "live" on its own.
                Text("Live")
                    .font(.hotMess(.footnote))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Bubbles are at most 280 wide or 75% of the space inside the panel.
    private var maxBubbleWidth: CGFloat {
        guard width > 0 else { return ChatMetrics.bubbleMaxWidth }
        return min(ChatMetrics.bubbleMaxWidth, (width - 32) * ChatMetrics.bubbleMaxFraction)
    }

    private var accessibilityLabel: String {
        if let online, online > 0 {
            return recentLabel + ", " + String(localized: "\(online) here now")
        }
        return isLive ? recentLabel + ", " + String(localized: "live") : recentLabel
    }

    private var recentLabel: String {
        switch visible.count {
        case 0:
            String(localized: "Open the chat at \(roomName), no messages yet")
        case 1:
            String(localized: "Open the chat at \(roomName), 1 recent message")
        default:
            String(localized: "Open the chat at \(roomName), \(visible.count) recent messages")
        }
    }
}

/// ChatPeek's edge while the room is live: a 2pt spectrum sweep turning once
/// every six seconds. It holds still with Reduce Motion, and stops while the
/// app isn't active. Decoration only; the header says the same in words.
private struct LiveRing: View {
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var turned = false

    static let period: TimeInterval = 6
    static let lineWidth: CGFloat = 2

    private var turns: Bool { !reduceMotion && scenePhase == .active }

    var body: some View {
        GeometryReader { proxy in
            // A square as wide as the panel's diagonal covers it at every angle.
            let side = (proxy.size.width * proxy.size.width + proxy.size.height * proxy.size.height).squareRoot()
            // The first band again at the end, so the loop has no seam.
            AngularGradient(
                colors: Color.hotMessSpectrum + [Color.hotMessSpectrum[0]],
                center: .center
            )
            .frame(width: side, height: side)
            .rotationEffect(.degrees(turned ? 360 : 0))
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .mask {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(lineWidth: Self.lineWidth)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: turns, initial: true) { _, turns in
            if turns {
                withAnimation(.linear(duration: Self.period).repeatForever(autoreverses: false)) {
                    turned = true
                }
            } else {
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { turned = false }
            }
        }
    }
}

/// One bubble in a peek: name above the first incoming bubble of a group,
/// avatar beside the last, text clamped to two lines. No time dividers.
private struct ChatPeekRow: View {
    let row: ChatThreadRow
    let maxBubbleWidth: CGFloat

    private var message: ChatThreadMessage { row.message }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !message.isOwn {
                if row.isLastInGroup {
                    ChatAvatar(message: message, presenceRing: .hotMessSurfaceSunken, compact: true)
                } else {
                    Color.clear
                        .frame(width: ChatMetrics.avatarDiameter(for: message, compact: true), height: 1)
                }
            }

            VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 2) {
                if !message.isOwn, row.isFirstInGroup {
                    ChatSenderLine(name: message.authorName, role: message.role)
                        .padding(.leading, 12)
                }

                // Rich messages show their summary at a bubble's size.
                ChatBubble(
                    text: message.text,
                    isOwn: message.isOwn,
                    isLastInGroup: row.isLastInGroup,
                    isRole: message.role?.tintsBubble == true,
                    lineLimit: 2,
                    isSelectable: false,
                    label: message.promptLabel
                )
            }
            .frame(maxWidth: maxBubbleWidth, alignment: message.isOwn ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: message.isOwn ? .trailing : .leading)
        .padding(.top, topSpacing)
    }

    /// 2 between bubbles in a group, 8 between groups.
    private var topSpacing: CGFloat {
        if row.isFirstRow { return 0 }
        return row.isFirstInGroup ? 8 : 2
    }
}

extension [VenueMessage] {
    /// Recent messages as a ChatPeek shows them: specials that have ended
    /// left out, friends by their full name, rich messages as their summary.
    func peekMessages(currentUserID: UUID?, friends: [UUID: Friend], at date: Date = .now) -> [ChatThreadMessage] {
        filter { $0.isShowing(at: date) }
            .map { $0.threadMessage(currentUserID: currentUserID, friends: friends, rich: false) }
    }
}

// MARK: - Previews

private enum ChatPeekPreviewData {
    static let start = Date(timeIntervalSince1970: 1_791_590_400)

    static let messages: [ChatThreadMessage] = [
        ChatThreadMessage(
            id: "1", authorID: "sam", authorName: "Sam B.", avatarURL: nil,
            text: "Anyone at the bar?", sentAt: start, isOwn: false
        ),
        ChatThreadMessage(
            id: "2", authorID: "sam", authorName: "Sam B.", avatarURL: nil,
            text: "DJ just started. This is a much longer message to show how a peek clamps a bubble to two lines with an ellipsis.",
            sentAt: start.addingTimeInterval(60), isOwn: false, presence: .online
        ),
        ChatThreadMessage(
            id: "3", authorID: "me", authorName: "Me", avatarURL: nil,
            text: "On my way, save me a spot", sentAt: start.addingTimeInterval(120), isOwn: true
        ),
    ]
}

#Preview("ChatPeek") {
    NavigationStack {
        ScrollView {
            VStack(spacing: 24) {
                ChatPeek(
                    title: "Chat",
                    roomName: "The Eagle",
                    messages: ChatPeekPreviewData.messages,
                    online: 4
                ) {}

                ChatPeek(
                    title: "Small talk",
                    roomName: "The Eagle",
                    messages: ChatPeekPreviewData.messages,
                    online: 4,
                    isLive: true
                ) {}

                ChatPeek(title: "Small talk", roomName: "The Eagle", messages: []) {}
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemGroupedBackground))
    }
}
