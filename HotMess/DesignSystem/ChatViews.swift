//
//  ChatViews.swift
//  HotMess
//

import SwiftUI
import UIKit

// The shared chat kit (design system "Chat"): ChatThreadView and ChatBubble for
// a room's transcript, RoomBanner, PinnedBar, ChatComposer, PresenceDot,
// RoleTag and ChatLine. Rich messages are in RichMessage.swift, and an event's
// chat prompts (PromptBar, TriviaCard, PromptCard) in ChatPrompts.swift.
// None of these know about venues: rooms pass their title as `roomName`, so a
// venue room and a locale-wide room share them.

/// Chat metrics from the design system's tokens.
enum ChatMetrics {
    /// `radius-bubble`.
    static let bubbleRadius: CGFloat = HotMessRadius.bubble
    /// `radius-sm`: the "tail" corner of a group's last bubble.
    static let tailRadius: CGFloat = HotMessRadius.sm
    /// `size-bubble-max`.
    static let bubbleMaxWidth: CGFloat = 280
    /// Bubbles are never wider than this share of the transcript.
    static let bubbleMaxFraction: CGFloat = 0.75
    /// Rich messages (cards) are up to this wide, or `richMaxFraction` of the transcript.
    static let richMaxWidth: CGFloat = 320
    static let richMaxFraction: CGFloat = 0.85
    /// A TinyAvatar: chat avatars are small on purpose, so a room is for
    /// finding friends, not judging strangers' photos.
    static let avatarSize: CGFloat = 24
    /// A TinyAvatar in ChatPeek.
    static let peekAvatarSize: CGFloat = 20
    /// `size-avatar-sm`: the venue, and talent posting as their listing,
    /// keep their photos at this size.
    static let listingAvatarSize: CGFloat = 28
    /// A PromptCard is at most this wide, centred in the thread.
    static let promptCardMaxWidth: CGFloat = 330

    /// How big a sender's avatar draws: 28 for the venue and talent posting
    /// as their listing, else 24 (20 in ChatPeek).
    static func avatarDiameter(for message: ChatThreadMessage, compact: Bool = false) -> CGFloat {
        if message.isFromListing, !message.isFromAudience { return listingAvatarSize }
        return compact ? peekAvatarSize : avatarSize
    }
    /// Messages from one sender closer together than this form a group.
    static let groupGap: TimeInterval = 5 * 60
    /// A time divider follows any gap at least this long.
    static let dividerGap: TimeInterval = 15 * 60
}

/// How chat formats times.
enum ChatTime {
    /// A time divider's label, like "Fri 9 PM" or "Fri 9:26 PM".
    static func divider(_ date: Date, calendar: Calendar = .current) -> String {
        let style = Date.FormatStyle.dateTime
            .weekday(.abbreviated)
            .hour(.defaultDigits(amPM: .abbreviated))

        if calendar.component(.minute, from: date) == 0 {
            return date.formatted(style)
        }

        return date.formatted(style.minute(.twoDigits))
    }

    /// A compact age for chat previews: "now", "2m", "3h", "4d".
    static func relative(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))

        switch seconds {
        case ..<60:
            return String(localized: "now")
        case ..<3600:
            return String(localized: "\(Int(seconds / 60))m")
        case ..<86_400:
            return String(localized: "\(Int(seconds / 3600))h")
        default:
            return String(localized: "\(Int(seconds / 86_400))d")
        }
    }
}

// MARK: - Presence

/// Whether someone can be reached right now.
enum PresenceState: String, Codable, Hashable, Sendable {
    /// Connected to a chat room now.
    case online
    /// Not in chat, but has a device that gets push notifications.
    case push
    /// Neither. Draws nothing.
    case offline
}

/// Green when someone is in chat, a yellow ring when they'll get a push
/// notification, nothing otherwise (or a gray dot, with `showsOffline`).
/// Usually drawn by `Avatar(presence:)`.
struct PresenceDot: View {
    let state: PresenceState
    /// 10 on 28 avatars, 12 on 40 and up. The ring adds 2 on each side.
    var size: CGFloat = 10
    /// The ring that separates the dot from the photo under it.
    var ringColor: Color = Color(.secondarySystemGroupedBackground)
    /// Draw `.offline` as a gray dot instead of nothing: for someone a chat
    /// room still lists after they left.
    var showsOffline = false

    var body: some View {
        switch state {
        case .online:
            Circle()
                .fill(Color.hotMessPresenceOnline)
                .frame(width: size, height: size)
                .modifier(PresenceRing(color: ringColor, label: String(localized: "In chat now")))
        case .push:
            ZStack {
                Circle()
                    .fill(Color.hotMessPresencePush)
                Circle()
                    .fill(ringColor)
                    .frame(width: size * 0.45, height: size * 0.45)
                Circle()
                    .strokeBorder(Color.hotMessPresencePushEdge, lineWidth: 1)
            }
            .frame(width: size, height: size)
            .modifier(PresenceRing(color: ringColor, label: String(localized: "Gets notifications")))
        case .offline:
            if showsOffline {
                Circle()
                    .fill(Color(.systemGray3))
                    .frame(width: size, height: size)
                    .modifier(PresenceRing(color: ringColor, label: String(localized: "Here recently")))
            }
        }
    }
}

private struct PresenceRing: ViewModifier {
    let color: Color
    let label: String

    func body(content: Content) -> some View {
        content
            .padding(2)
            .background(color, in: .circle)
            .accessibilityElement()
            .accessibilityLabel(label)
    }
}

// MARK: - Thread

/// One message as a chat room shows it. Rooms map their own message model to
/// this in the view layer.
struct ChatThreadMessage: Identifiable, Hashable, Sendable {
    let id: String
    /// Messages group by this, so it must be stable per sender.
    let authorID: String
    let authorName: String?
    let avatarURL: URL?
    let text: String
    /// When it was sent. Without one, the message joins its sender's group and
    /// no time divider is drawn around it.
    let sentAt: Date?
    /// Sent by the person reading.
    let isOwn: Bool
    var presence: PresenceState? = nil
    /// Only the reader's own lines are ever anything but `.sent`.
    var delivery: ChatDelivery = .sent
    /// The sender's role in the room: a tag after their name, and a tinted
    /// bubble for the venue and hosts.
    var role: ChatRole? = nil
    /// Posted as the venue: its photo in a rounded square, never a presence dot.
    var isFromPlace = false
    /// Posted as the venue or by talent as their listing: its avatar keeps
    /// its 28 size.
    var isFromListing = false
    /// Posted as the audience (a prompt): the audience's mark, no presence,
    /// and nobody to block.
    var isFromAudience = false
    /// What a host, the venue or staff posted besides text. `text` is then
    /// its summary in words, for VoiceOver and previews.
    var rich: ChatRichContent? = nil
    /// "Prompt" or "Trivia" over a text line that answers a prompt.
    var promptLabel: String? = nil
    /// The prompt a text line answers, by ID: its label goes to that prompt.
    var promptID: String? = nil
    /// A prompt dropped into a quiet room, drawn as a PromptCard.
    var promptCard: ChatPrompt? = nil

    /// Someone the reader can tap for their profile sheet: another person
    /// posting as themself. Not the venue, talent posting as their listing,
    /// a prompt (the audience), or the reader's own lines.
    var opensProfile: Bool {
        !isOwn && !isFromPlace && !isFromListing && !isFromAudience && delivery == .sent
            && UUID(uuidString: authorID) != nil
    }

    /// The announcement's title, when this is one.
    var announcementTitle: String? {
        if case let .announcement(title, _, _, _) = rich { return title }
        return nil
    }
}

/// A rich message's content (design system "RichMessage").
enum ChatRichContent: Hashable, Sendable {
    /// A title, a body and an optional photo.
    case announcement(title: String, body: String?, photoURL: URL?, isPinned: Bool)
    /// One of the audience's events, with an optional caption.
    case event(SharedEvent, caption: String?)
    /// A photo with an optional caption.
    case photo(URL, caption: String?)
    /// A title and body that show until `endsAt`.
    case special(title: String, body: String?, endsAt: Date?)
    /// A song request or karaoke signup, where it stands, and the note to
    /// the host.
    case request(ChatSongRequest, note: String?)
}

/// Where a transcript divides what has cleared from what is current.
struct ChatClearMark: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// An admin cleared the room at `at`.
        case cleared
        /// Lines before `at` have expired for everyone but the room's admins.
        case expired
    }

    let at: Date
    let kind: Kind

    /// What the divider says.
    var label: String {
        switch kind {
        case .cleared:
            String(localized: "Chat cleared at \(at.formatted(date: .omitted, time: .shortened))")
        case .expired:
            String(localized: "Cleared for everyone but admins above")
        }
    }
}

/// Where one of the reader's own lines is on its way to the room.
enum ChatDelivery: Hashable, Sendable {
    case sent
    case sending
    /// Didn't reach the room; tapping it tries again.
    case failed
}

/// A chat room's transcript: bubbles grouped by sender, with time dividers and
/// an empty state. Oldest first, kept scrolled to the newest message.
struct ChatThreadView: View {
    let messages: [ChatThreadMessage]
    /// The room's name, for the empty state ("Everyone at {name} can see…").
    let roomName: String
    /// The announcement pinned under the room's title, drawn as a PinnedBar
    /// that scrolls to it. It must be one of `messages`.
    var pinned: ChatThreadMessage? = nil
    /// Called with a failed message's ID when the reader taps it.
    var onRetry: ((String) -> Void)? = nil
    /// Report and Block, in the menu on someone else's message. Without them
    /// there's no menu.
    var onReport: ((ChatThreadMessage) -> Void)? = nil
    var onBlock: ((ChatThreadMessage) -> Void)? = nil
    /// Delete, in the menu on the reader's own sent messages. Without it
    /// their messages have no menu.
    var onDelete: ((ChatThreadMessage) -> Void)? = nil
    /// Tonight's prompt, drawn under the title (after any PinnedBar) as a
    /// PromptBar, or a TriviaCard for trivia.
    var prompt: ChatPrompt? = nil
    /// How many answers to `prompt` the room has shown.
    var promptAnswers = 0
    /// The time to draw against: when a trivia answer reveals itself.
    var now: Date = .now
    /// "Answer" on the PromptBar or a PromptCard. Without it there's no button.
    var onAnswer: ((ChatPrompt) -> Void)? = nil
    /// "Not now" on a PromptCard, with its message.
    var onDismissPrompt: ((ChatThreadMessage) -> Void)? = nil
    /// Where what has cleared ends and what is current begins, drawn as a
    /// labelled rule: above the first message sent since, or after them all.
    var clearMark: ChatClearMark? = nil
    /// Tapping someone's avatar or name: their profile sheet. Only for
    /// people posting as themselves (`opensProfile`).
    var onOpenProfile: ((ChatThreadMessage) -> Void)? = nil

    @State private var width: CGFloat = 0
    /// Scrolled back from the newest messages: the PromptBar folds to one line.
    @State private var isScrolledBack = false
    /// The reader opened the folded PromptBar (tapping it, or an answer's
    /// label). It folds again once they're back at the newest messages.
    @State private var isPromptExpanded = false
    /// The prompt an answer's label just went to, outlined for a moment.
    @State private var highlightedPromptID: String?
    @State private var highlightTask: Task<Void, Never>?

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if let pinned, let title = pinned.announcementTitle {
                    PinnedBar(author: pinned.authorName, title: title) {
                        withAnimation { proxy.scrollTo(pinned.id, anchor: .top) }
                    }
                }

                if let prompt {
                    // The header never holds more than two strips: under a
                    // pinned announcement the bar is one line.
                    PromptBar(
                        prompt: prompt,
                        answers: promptAnswers,
                        isCollapsed: (isScrolledBack || pinned?.announcementTitle != nil) && !isPromptExpanded,
                        now: now,
                        isHighlighted: highlightedPromptID == prompt.id,
                        onAnswer: onAnswer.map { answer in { answer(prompt) } },
                        onExpand: {
                            withAnimation(HotMessMotion.quick) { isPromptExpanded = true }
                        }
                    )
                    .id(prompt.id)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .animation(HotMessMotion.quick, value: isScrolledBack)
                }

                thread(proxy)
            }
        }
    }

    private func thread(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            if messages.isEmpty {
                if let clearMark {
                    ChatClearDivider(mark: clearMark)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
                ChatEmptyState(roomName: roomName)
            } else {
                let rows = ChatThreadRow.rows(for: messages, clearMark: clearMark)
                let reachable = reachablePromptIDs
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        ChatThreadRowView(
                            row: row,
                            maxBubbleWidth: maxBubbleWidth,
                            maxRichWidth: maxRichWidth,
                            now: now,
                            onRetry: onRetry,
                            onReport: onReport,
                            onBlock: onBlock,
                            onDelete: onDelete,
                            onAnswer: onAnswer,
                            onDismissPrompt: onDismissPrompt,
                            onOpenProfile: onOpenProfile,
                            onGoToPrompt: goToPromptAction(for: row.message, reachable: reachable, proxy: proxy),
                            highlightedPromptID: highlightedPromptID
                        )
                        .id(row.id)
                    }
                    if let clearMark, !rows.contains(where: \.opensAfterClear) {
                        ChatClearDivider(mark: clearMark)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { newValue in
            width = newValue
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.height - (geometry.contentOffset.y + geometry.containerSize.height) > 120
        } action: { _, scrolledBack in
            isScrolledBack = scrolledBack
            // Back at the newest messages: a bar the reader opened folds
            // again (under a pinned announcement). Only on the way back, so
            // the bar growing can't fold it as it opens.
            if !scrolledBack { isPromptExpanded = false }
        }
        .onChange(of: messages.count) { _, _ in
            guard let last = messages.last else { return }
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    /// The prompts an answer's label can go to: tonight's, in the bar, and
    /// the PromptCards in the thread. Older pinned prompts aren't drawn in
    /// the thread, so answers to them have nowhere to go.
    private var reachablePromptIDs: Set<String> {
        var ids = Set(messages.compactMap { $0.promptCard?.id })
        if let prompt { ids.insert(prompt.id) }
        return ids
    }

    /// What an answer's label does: go to its prompt, when that's on screen.
    private func goToPromptAction(
        for message: ChatThreadMessage,
        reachable: Set<String>,
        proxy: ScrollViewProxy
    ) -> (() -> Void)? {
        guard let id = message.promptID, reachable.contains(id) else { return nil }
        return { goToPrompt(id, proxy: proxy) }
    }

    /// An answer's label: opens and outlines the bar for tonight's prompt,
    /// or scrolls to the PromptCard and outlines that.
    private func goToPrompt(_ id: String, proxy: ScrollViewProxy) {
        if let prompt, prompt.id == id {
            withAnimation(HotMessMotion.quick) { isPromptExpanded = true }
            highlight(id)
        } else if let card = messages.last(where: { $0.promptCard?.id == id }) {
            withAnimation { proxy.scrollTo(card.id, anchor: .center) }
            highlight(id)
        }
    }

    private func highlight(_ id: String) {
        highlightTask?.cancel()
        withAnimation(HotMessMotion.quick) { highlightedPromptID = id }
        highlightTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { highlightedPromptID = nil }
        }
    }

    private var maxBubbleWidth: CGFloat {
        guard width > 0 else { return ChatMetrics.bubbleMaxWidth }
        return min(ChatMetrics.bubbleMaxWidth, (width - 32) * ChatMetrics.bubbleMaxFraction)
    }

    private var maxRichWidth: CGFloat {
        guard width > 0 else { return ChatMetrics.richMaxWidth }
        return min(ChatMetrics.richMaxWidth, (width - 32) * ChatMetrics.richMaxFraction)
    }
}

/// A message with where it falls in its group.
struct ChatThreadRow: Identifiable, Hashable, Sendable {
    let message: ChatThreadMessage
    /// A time divider to draw above this message, if one opens here.
    let divider: Date?
    let isFirstInGroup: Bool
    let isLastInGroup: Bool
    /// The first row of the transcript, which needs no space above.
    let isFirstRow: Bool
    /// Over a PromptCard: how long the room was quiet before it dropped in,
    /// in whole minutes ("Quiet for 10 minutes").
    var quietMinutes: Int? = nil
    /// The first message sent since the room's clear mark, with older ones
    /// above it: the clear divider goes over it.
    var clearMark: ChatClearMark? = nil

    var id: String { message.id }

    var opensAfterClear: Bool { clearMark != nil }

    static func rows(for messages: [ChatThreadMessage], clearMark: ChatClearMark? = nil) -> [ChatThreadRow] {
        let dividers = messages.indices.map { index in divider(at: index, in: messages) }
        let firstAfterClear = clearMark.flatMap { mark in
            messages.firstIndex { ($0.sentAt ?? .distantFuture) >= mark.at }
        }

        return messages.indices.map { index in
            let message = messages[index]
            let isFirst = index == 0
                || dividers[index] != nil
                || !sameGroup(messages[index - 1], message)
            let isLast = index == messages.count - 1
                || dividers[index + 1] != nil
                || !sameGroup(message, messages[index + 1])

            return ChatThreadRow(
                message: message,
                divider: dividers[index],
                isFirstInGroup: isFirst,
                isLastInGroup: isLast,
                isFirstRow: index == 0,
                quietMinutes: quietMinutes(at: index, in: messages),
                // Nothing cleared above the first message: the empty room or
                // the end of the transcript carries the mark instead.
                clearMark: index == firstAfterClear && index > 0 ? clearMark : nil
            )
        }
    }

    /// The quiet a PromptCard broke: the minutes since the line before it.
    private static func quietMinutes(at index: Int, in messages: [ChatThreadMessage]) -> Int? {
        guard messages[index].promptCard != nil, index > 0,
              let sentAt = messages[index].sentAt, let previous = messages[index - 1].sentAt
        else { return nil }

        let minutes = Int(sentAt.timeIntervalSince(previous) / 60)
        return minutes > 0 ? minutes : nil
    }

    private static func divider(at index: Int, in messages: [ChatThreadMessage]) -> Date? {
        guard let sentAt = messages[index].sentAt else { return nil }
        guard index > 0 else { return sentAt }
        guard let previous = messages[index - 1].sentAt else { return nil }

        return sentAt.timeIntervalSince(previous) >= ChatMetrics.dividerGap ? sentAt : nil
    }

    /// Rich messages and PromptCards stand alone: each shows its sender's
    /// name and avatar, and ends any group.
    private static func sameGroup(_ earlier: ChatThreadMessage, _ later: ChatThreadMessage) -> Bool {
        guard earlier.rich == nil, later.rich == nil else { return false }
        guard earlier.promptCard == nil, later.promptCard == nil else { return false }
        guard earlier.authorID == later.authorID, earlier.isOwn == later.isOwn else { return false }
        guard let earlierAt = earlier.sentAt, let laterAt = later.sentAt else { return true }

        return laterAt.timeIntervalSince(earlierAt) < ChatMetrics.groupGap
    }
}

private struct ChatThreadRowView: View {
    let row: ChatThreadRow
    let maxBubbleWidth: CGFloat
    let maxRichWidth: CGFloat
    var now: Date = .now
    let onRetry: ((String) -> Void)?
    var onReport: ((ChatThreadMessage) -> Void)? = nil
    var onBlock: ((ChatThreadMessage) -> Void)? = nil
    var onDelete: ((ChatThreadMessage) -> Void)? = nil
    var onAnswer: ((ChatPrompt) -> Void)? = nil
    var onDismissPrompt: ((ChatThreadMessage) -> Void)? = nil
    var onOpenProfile: ((ChatThreadMessage) -> Void)? = nil
    /// The answer's label, when the prompt it answers is on screen.
    var onGoToPrompt: (() -> Void)? = nil
    var highlightedPromptID: String? = nil

    private var message: ChatThreadMessage { row.message }

    /// The sender's avatar and name open their profile sheet.
    private var canOpenProfile: Bool {
        message.opensProfile && onOpenProfile != nil
    }

    /// The reader's own message that reached the room.
    private var canDelete: Bool {
        message.isOwn && message.delivery == .sent && onDelete != nil
    }

    /// Someone else's message that reached the room, including a post as the
    /// venue (or a person), which can be reported too.
    private var canReport: Bool {
        !message.isOwn && message.delivery == .sent && onReport != nil
    }

    /// A post as the venue is the venue's own, and a prompt the audience's,
    /// so neither has a sender to block.
    private var canBlock: Bool {
        canReport && !message.isFromPlace && !message.isFromAudience && onBlock != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if let clearMark = row.clearMark {
                ChatClearDivider(mark: clearMark)
                    .padding(.top, 12)
                    .padding(.bottom, row.divider == nil ? 4 : 0)
            }

            if let divider = row.divider {
                ChatDividerLabel(text: ChatTime.divider(divider))
                    .padding(.top, row.isFirstRow ? 0 : 12)
                    .padding(.bottom, 4)
            }

            if let prompt = message.promptCard {
                promptCard(prompt)
            } else {
                line
            }
        }
        .padding(.top, topSpacing)
    }

    /// A prompt dropped into a quiet room: centred, with why it appeared above it.
    private func promptCard(_ prompt: ChatPrompt) -> some View {
        VStack(spacing: 4) {
            if let minutes = row.quietMinutes {
                ChatDividerLabel(text: minutes == 1
                    ? String(localized: "Quiet for 1 minute")
                    : String(localized: "Quiet for \(minutes) minutes"))
                    .padding(.top, row.isFirstRow || row.divider != nil ? 0 : 4)
            }

            PromptCard(
                prompt: prompt,
                author: message.authorName,
                sentAt: message.sentAt,
                now: now,
                onAnswer: onAnswer.map { answer in { answer(prompt) } },
                onDismiss: onDismissPrompt.map { dismiss in { [message] in dismiss(message) } },
                isHighlighted: highlightedPromptID == prompt.id
            )
            .id(prompt.id)
            .frame(maxWidth: ChatMetrics.promptCardMaxWidth)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var line: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !message.isOwn {
                if row.isLastInGroup {
                    profileButton(horizontalSlop: 8, verticalSlop: 10) {
                        ChatAvatar(message: message)
                    }
                    .accessibilityHidden(true)
                } else {
                    Color.clear
                        .frame(width: ChatMetrics.avatarDiameter(for: message), height: 1)
                }
            }

            VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 2) {
                // The reader's own posts as the venue name it the way
                // everyone else sees them ("Try-Angles [Venue]"); their
                // ordinary messages as themselves need no name.
                if row.isFirstInGroup, !message.isOwn || message.isFromPlace {
                    profileButton(horizontalSlop: 0, verticalSlop: 14) {
                        ChatSenderLine(name: message.authorName, role: message.role)
                    }
                    .padding(message.isOwn ? .trailing : .leading, message.rich == nil ? 12 : 4)
                    .accessibilityHidden(true)
                }

                Group {
                    if let rich = message.rich {
                        RichMessageView(content: rich)
                    } else {
                        ChatBubble(
                            text: message.text,
                            isOwn: message.isOwn,
                            isLastInGroup: row.isLastInGroup,
                            isRole: message.role?.tintsBubble == true,
                            label: message.promptLabel,
                            onLabelTap: onGoToPrompt
                        )
                    }
                }
                .opacity(message.delivery == .sent ? 1 : 0.6)
                .accessibilityElement(children: message.rich == nil ? .ignore : .contain)
                .accessibilityLabel(accessibilityLabel)
                .contextMenu {
                    if canReport {
                        moderationActions
                    }
                    if canDelete {
                        deleteAction
                    }
                }
                .accessibilityActions {
                    if canOpenProfile, let onOpenProfile {
                        Button(profileActionTitle) { onOpenProfile(message) }
                    }
                    if let onGoToPrompt {
                        Button(String(localized: "Go to the prompt"), action: onGoToPrompt)
                    }
                    if canReport {
                        moderationActions
                    }
                    if canDelete {
                        deleteAction
                    }
                }

                deliveryStatus
            }
            .frame(
                maxWidth: message.rich == nil ? maxBubbleWidth : maxRichWidth,
                alignment: message.isOwn ? .trailing : .leading
            )
        }
        .frame(maxWidth: .infinity, alignment: message.isOwn ? .trailing : .leading)
    }

    /// The avatar or name as a button to the profile sheet, its hit area
    /// grown by the slop toward 44pt without moving anything; or as it is,
    /// for a sender with no profile sheet.
    @ViewBuilder
    private func profileButton<Content: View>(
        horizontalSlop: CGFloat,
        verticalSlop: CGFloat,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        if canOpenProfile, let onOpenProfile {
            Button {
                onOpenProfile(message)
            } label: {
                content()
                    .padding(.horizontal, horizontalSlop)
                    .padding(.vertical, verticalSlop)
                    .contentShape(.rect)
                    .padding(.horizontal, -horizontalSlop)
                    .padding(.vertical, -verticalSlop)
            }
            .buttonStyle(.plain)
        } else {
            content()
        }
    }

    private var profileActionTitle: String {
        if let name = message.authorName, !name.isEmpty {
            return String(localized: "View \(name)'s profile")
        }
        return String(localized: "View profile")
    }

    @ViewBuilder
    private var moderationActions: some View {
        Button {
            onReport?(message)
        } label: {
            Label(String(localized: "Report…"), systemImage: "exclamationmark.bubble")
        }

        if canBlock, let onBlock {
            Button(role: .destructive) {
                onBlock(message)
            } label: {
                Label(blockTitle, systemImage: "hand.raised")
            }
        }
    }

    private var deleteAction: some View {
        Button(role: .destructive) {
            onDelete?(message)
        } label: {
            Label(String(localized: "Delete"), systemImage: "trash")
        }
    }

    private var blockTitle: String {
        if let name = message.authorName, !name.isEmpty {
            return String(localized: "Block \(name)")
        }
        return String(localized: "Block")
    }

    @ViewBuilder
    private var deliveryStatus: some View {
        switch message.delivery {
        case .sent:
            EmptyView()
        case .sending:
            Text("Sending…")
                .font(.hotMess(.caption))
                .foregroundStyle(.secondary)
                .padding(.trailing, 4)
        case .failed:
            Button {
                onRetry?(message.id)
            } label: {
                Label(String(localized: "Not sent. Tap to retry."), systemImage: "exclamationmark.circle")
                    .font(.hotMess(.caption, semibold: true))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
    }

    /// 2 between bubbles in a group, 8 between groups.
    private var topSpacing: CGFloat {
        if row.isFirstRow || row.divider != nil { return 0 }
        return row.isFirstInGroup ? 8 : 2
    }

    private var accessibilityLabel: String {
        // "Prompt answer: …" says what the label on the bubble does.
        let text = message.promptLabel.map { String(localized: "\($0) answer: \(message.text)") } ?? message.text
        if message.isOwn {
            if let name = message.authorName, !name.isEmpty, let role = message.role {
                return String(localized: "You, as \(name), \(role.title): \(text)")
            }
            return String(localized: "You: \(text)")
        }
        let name = message.authorName.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Someone")
        if let role = message.role {
            return "\(name), \(role.title): \(text)"
        }
        return "\(name): \(text)"
    }
}

/// A centred caption between lines of the thread: a time divider, or why a
/// PromptCard appeared.
struct ChatDividerLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.hotMess(.caption, semibold: true))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A sender's avatar beside their bubbles (a TinyAvatar): round with presence
/// for people at 24, a rounded square with no presence for a post as the
/// venue and talent's listing photo at 28, and the audience's mark for a prompt.
struct ChatAvatar: View {
    let message: ChatThreadMessage
    /// The surface behind the avatar, for the presence dot's ring.
    var presenceRing: Color = Color(.secondarySystemGroupedBackground)
    /// ChatPeek's 20 instead of 24.
    var compact = false

    var body: some View {
        let size = ChatMetrics.avatarDiameter(for: message, compact: compact)

        if message.isFromAudience {
            AudienceMark(name: message.authorName, size: size)
        } else {
            Avatar(
                url: message.avatarURL,
                initials: message.authorName?.initialsForDisplay,
                size: size,
                presence: message.isFromListing ? nil : message.presence,
                presenceRing: presenceRing,
                isPlace: message.isFromPlace,
                tintsInitials: !message.isFromListing
            )
        }
    }
}

/// The sender's name above the first incoming bubble of a group, with their
/// RoleTag after it.
struct ChatSenderLine: View {
    let name: String?
    let role: ChatRole?

    var body: some View {
        if (name?.isEmpty == false) || role != nil {
            HStack(spacing: 6) {
                if let name, !name.isEmpty {
                    Text(name)
                        .font(.hotMess(.caption, semibold: true))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let role {
                    RoleTag(role: role)
                }
            }
        }
    }
}

// MARK: - Roles

extension ChatRole {
    /// The tag's word: "Venue", "Host", "Staff".
    var title: String {
        switch self {
        case .venue: String(localized: "Venue")
        case .host: String(localized: "Host")
        case .staff: String(localized: "Staff")
        }
    }

    /// The venue and hosts get an `accent-soft` bubble; staff a normal one.
    var tintsBubble: Bool {
        self == .venue || self == .host
    }
}

/// The pill after a sender's name that says who they are in the room. It's a
/// word, so the tint never carries meaning alone.
struct RoleTag: View {
    let role: ChatRole

    var body: some View {
        Text(role.title)
            .font(.hotMess(fixedSize: 11, semibold: true))
            .tracking(0.2)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(minHeight: 16)
            .background(background, in: .capsule)
            .fixedSize()
    }

    private var foreground: Color {
        switch role {
        case .venue: .hotMessOnAccent
        case .host: .hotMessAccentInk
        case .staff: .primary
        }
    }

    private var background: Color {
        switch role {
        case .venue: .hotMessAccent
        case .host: .hotMessAccentSoft
        case .staff: .hotMessControlFill
        }
    }
}

/// One chat bubble. The last bubble of a group drops its corner nearest the
/// sender to a small "tail".
struct ChatBubble: View {
    let text: String
    let isOwn: Bool
    var isLastInGroup: Bool = true
    /// From the venue or a host: `accent-soft` with primary text, no shadow.
    /// Ignored on the reader's own bubbles.
    var isRole: Bool = false
    /// Lines of text before an ellipsis; `nil` shows it all.
    var lineLimit: Int? = nil
    /// Off where the bubble sits inside a button, like ChatPeek.
    var isSelectable: Bool = true
    /// "Prompt" or "Trivia" on a line that answers one, in a first line of
    /// its own with a reply glyph. It doesn't change grouping.
    var label: String? = nil
    /// Tapping the label: go to the prompt the line answers. Without it the
    /// label is only text.
    var onLabelTap: (() -> Void)? = nil

    var body: some View {
        if isSelectable {
            bubble.textSelection(.enabled)
        } else {
            bubble
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label {
                if let onLabelTap {
                    Button(action: onLabelTap) {
                        promptLabel(label)
                            // A 44pt target around the small label, without
                            // making the bubble any taller.
                            .padding(.vertical, Self.labelHitPadding)
                            .padding(.horizontal, 8)
                            .contentShape(.rect)
                            .padding(.vertical, -Self.labelHitPadding)
                            .padding(.horizontal, -8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Go to the prompt"))
                    .accessibilityIdentifier("chat.promptLabel")
                } else {
                    promptLabel(label)
                }
            }

            Text(text)
                .font(.hotMess(.subheadline))
                .foregroundStyle(isOwn ? Color.hotMessOnAccent : Color.primary)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if isOwn {
                shape.fill(Color.hotMessAccent)
            } else if isRole {
                shape.fill(Color.hotMessAccentSoft)
            } else {
                shape
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.12), radius: 1, x: 0, y: 1)
            }
        }
    }

    /// Grows the label's ~16pt line to a 44pt hit area.
    private static let labelHitPadding: CGFloat = 14

    private func promptLabel(_ label: String) -> some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 10, weight: .semibold))
        }
        .labelStyle(PromptLabelStyle())
        .font(.hotMess(fixedSize: 12, semibold: true))
        .foregroundStyle(isOwn ? Color.hotMessOnAccent : Color.secondary)
        .lineLimit(1)
    }

    private var shape: UnevenRoundedRectangle {
        let tail = isLastInGroup ? ChatMetrics.tailRadius : ChatMetrics.bubbleRadius
        let radius = ChatMetrics.bubbleRadius

        return UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: isOwn ? radius : tail,
            bottomTrailingRadius: isOwn ? tail : radius,
            topTrailingRadius: radius,
            style: .continuous
        )
    }
}

/// The Prompt label's glyph and word, close together.
private struct PromptLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

/// An empty room: "Say hello."
/// A rule across the transcript with what cleared in the middle: an admin
/// clearing the room, or the line past which only admins still see messages.
struct ChatClearDivider: View {
    let mark: ChatClearMark

    var body: some View {
        HStack(spacing: 8) {
            rule
            Text(mark.label)
                .font(.hotMess(.caption, semibold: true))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .layoutPriority(1)
            rule
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mark.label)
        .accessibilityIdentifier("chat.clearDivider")
    }

    private var rule: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.4))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

struct ChatEmptyState: View {
    let roomName: String

    var body: some View {
        VStack(spacing: 4) {
            Text("Say hello.")
                .font(.hotMess(.headline, semibold: true))
            Text("Everyone at \(roomName) can see what you write here.")
                .font(.hotMess(.subheadline))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 40)
    }
}

// MARK: - Banner

/// The strip under a room's title that says why the reader is (or isn't
/// fully) in the room. Only one shows; `range` wins.
struct RoomBanner: View {
    enum Kind: Hashable, Sendable {
        /// An admin in the room from outside the place it's for.
        case range
        case connecting
        /// The connection's own reason when it gave one, else a plain "Offline."
        case offline(String?)
    }

    let kind: Kind
    let roomName: String
    /// A locale-wide room: "not in {city}" rather than "not at {venue}".
    var isLocale = false

    var body: some View {
        switch kind {
        case .range:
            HStack(spacing: 8) {
                Image(systemName: "location.slash")
                    .foregroundStyle(Color.hotMessWarning)
                    .accessibilityHidden(true)
                Group {
                    if isLocale {
                        Text("You're not in \(roomName). You're in this chat because you're an admin.")
                    } else {
                        Text("You're not at \(roomName). You're in this chat because you're an admin.")
                    }
                }
                .foregroundStyle(.primary)
            }
            .font(.hotMess(.footnote))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.hotMessWarningSoft)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("chat.outOfRange")
        case .connecting, .offline:
            Text(stripText)
                .font(.hotMess(.footnote))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill))
                .accessibilityIdentifier(kind == .connecting ? "chat.connecting" : "chat.offline")
        }
    }

    private var stripText: String {
        switch kind {
        case .connecting: String(localized: "Connecting…")
        case let .offline(reason): reason ?? String(localized: "Offline.")
        case .range: ""
        }
    }
}

// MARK: - Pinned

/// The pinned announcement under a room's title. Tapping it scrolls to the
/// announcement.
struct PinnedBar: View {
    let author: String?
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.hotMessAccentInk)
                    .accessibilityHidden(true)

                label
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.hotMess(.footnote))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.hotMessAccentSoft)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Pinned announcement: \(title)"))
        .accessibilityHint(String(localized: "Shows it in the chat"))
        .accessibilityIdentifier("chat.pinned")
    }

    /// The author in bold, then the title, truncating as one line.
    private var label: Text {
        guard let author, !author.isEmpty else { return Text(title) }
        let bold = Text(author).font(.hotMess(.footnote, semibold: true))
        return Text("\(bold) \(title)")
    }
}

// MARK: - Composer

/// The message field and send button pinned to the bottom of a room. Sending
/// is the room's own code; this is only the look.
struct ChatComposer: View {
    @Binding var text: String
    /// False while the field is empty or the room is offline.
    let canSend: Bool
    /// The prompt the next line answers, after "Answer": an answer chip over
    /// the field and a hint under it.
    var answering: ChatPrompt? = nil
    /// The chip's close button.
    var stopAnswering: () -> Void = {}
    let send: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let answering {
                AnswerChip(prompt: answering, close: stopAnswering)
            }

            field

            if answering != nil {
                Text("Your answer shows in the room with a Prompt label.")
                    .font(.hotMess(.caption))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .top) {
            Divider()
        }
        .animation(HotMessMotion.quick, value: answering?.id)
        // "Answer" opens the composer.
        .onChange(of: answering?.id) { _, id in
            if id != nil { isFocused = true }
        }
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(String(localized: "Message"), text: $text, axis: .vertical)
                .focused($isFocused)
                .textFieldStyle(.plain)
                .font(.hotMess(.body))
                .lineLimit(1 ... 4)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minHeight: 40)
                .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color(.systemGray), lineWidth: 1)
                }

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(canSend ? Color.hotMessOnAccent : Color.secondary)
                    .frame(width: 40, height: 40)
                    .background(canSend ? Color.hotMessAccent : Color(.tertiarySystemFill), in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(String(localized: "Send"))
        }
    }
}

// MARK: - Chat line

/// A flat, bubble-less chat message: the Now screen's "Small talk" preview.
struct ChatLine: View {
    /// Falls back to "Someone".
    let author: String?
    let avatarURL: URL?
    let text: String
    /// Pre-formatted, like "2m".
    let time: String
    var presence: PresenceState? = nil
    /// Lines of text before an ellipsis; `nil` shows it all.
    var lineLimit: Int? = 2

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(
                url: avatarURL,
                initials: author?.initialsForDisplay,
                size: ChatMetrics.avatarSize,
                presence: presence
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(displayAuthor)
                        .font(.hotMess(.caption, semibold: true))
                    Text(time)
                        .font(.hotMess(.caption))
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Text(text)
                    .font(.hotMess(.subheadline))
                    .lineLimit(lineLimit)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var displayAuthor: String {
        guard let author, !author.isEmpty else { return String(localized: "Someone") }
        return author
    }
}

// MARK: - Previews

private enum ChatPreviewData {
    static let start = Date(timeIntervalSince1970: 1_791_590_400) // A Friday, 9pm UTC.

    static func message(
        _ index: Int,
        _ author: String,
        _ text: String,
        minutes: Double,
        own: Bool = false,
        presence: PresenceState? = nil
    ) -> ChatThreadMessage {
        ChatThreadMessage(
            id: "\(index)",
            authorID: own ? "me" : author,
            authorName: own ? "Me" : author,
            avatarURL: nil,
            text: text,
            sentAt: start.addingTimeInterval(minutes * 60),
            isOwn: own,
            presence: presence
        )
    }

    static let messages: [ChatThreadMessage] = [
        message(0, "Sam", "Anyone at the bar?", minutes: 0),
        message(1, "Sam", "The line's out the door", minutes: 1, presence: .online),
        message(2, "Alex", "Just got here", minutes: 3, presence: .push),
        message(3, "Me", "On my way, save me a spot", minutes: 4, own: true),
        message(4, "Me", "Five minutes", minutes: 4.5, own: true),
        message(5, "Sam", "DJ just started. This is a much longer message to show how a bubble wraps when it runs past the maximum width.", minutes: 25, presence: .online),
        message(6, "Me", "🔥", minutes: 26, own: true),
    ]
}

#Preview("Thread") {
    NavigationStack {
        VStack(spacing: 0) {
            RoomBanner(kind: .range, roomName: "The Eagle")
            ChatThreadView(messages: ChatPreviewData.messages, roomName: "The Eagle")
            ChatComposer(text: .constant(""), canSend: false) {}
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("The Eagle")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Empty, connecting") {
    VStack(spacing: 0) {
        RoomBanner(kind: .connecting, roomName: "The Eagle")
        ChatThreadView(messages: [], roomName: "The Eagle")
        ChatComposer(text: .constant("Hi"), canSend: true) {}
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Banners") {
    VStack(spacing: 12) {
        RoomBanner(kind: .range, roomName: "The Eagle")
        RoomBanner(kind: .connecting, roomName: "The Eagle")
        RoomBanner(kind: .offline(nil), roomName: "The Eagle")
    }
}

#Preview("Bubbles") {
    VStack(alignment: .leading, spacing: 2) {
        ChatBubble(text: "In a group", isOwn: false, isLastInGroup: false)
        ChatBubble(text: "Last of the group", isOwn: false)
        ChatBubble(text: "Mine", isOwn: true)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Presence") {
    HStack(spacing: 16) {
        Avatar(url: nil, initials: "SA", size: 24, presence: .online, tintsInitials: true)
        Avatar(url: nil, initials: "AL", size: 24, presence: .push, tintsInitials: true)
        Avatar(url: nil, initials: "JO", size: 20, presence: .offline, tintsInitials: true)
        Avatar(url: nil, initials: "SA", size: 56, presence: .online)
        Avatar(url: nil, initials: "AL", size: 56, presence: .push)
    }
    .padding()
    .background(Color(.secondarySystemGroupedBackground))
}

#Preview("Chat lines") {
    VStack(alignment: .leading, spacing: 12) {
        ChatLine(author: "Sam", avatarURL: nil, text: "The line's out the door", time: "2m", presence: .online)
        ChatLine(author: nil, avatarURL: nil, text: "A longer line that runs past two lines on a phone so it shows the ellipsis at the end of the second line.", time: "1h")
    }
    .padding()
}
