//
//  RichMessage.swift
//  HotMess
//

import SwiftUI

/// What hosts, the venue and staff can post besides text (design system
/// "RichMessage"): an announcement, a shared event, a photo or a special;
/// and anyone's song request or karaoke signup. Each stands alone in the
/// thread, up to 320 wide (or 85% of the room), except a photo, which is at
/// most 240.
struct RichMessageView: View {
    let content: ChatRichContent

    var body: some View {
        switch content {
        case let .announcement(title, text, photoURL, isPinned):
            announcement(title: title, text: text, photoURL: photoURL, isPinned: isPinned)
        case let .event(event, caption):
            SharedEventMessage(event: event, caption: caption)
        case let .photo(url, caption):
            photo(url: url, caption: caption)
        case let .special(title, text, endsAt):
            special(title: title, text: text, endsAt: endsAt)
        case let .request(request, note):
            self.request(request, note: note)
        }
    }

    // MARK: - Kinds

    /// An `accent-soft` card: an optional 16:9 photo, then the overline, title and body.
    private func announcement(title: String, text: String?, photoURL: URL?, isPinned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let photoURL {
                RichPhoto(url: photoURL, aspectRatio: 16 / 9)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                RichOverline(text: isPinned ? String(localized: "Pinned announcement") : String(localized: "Announcement"))
                RichTitleAndBody(title: title, text: text)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.hotMessAccentSoft)
        .clipShape(.rect(cornerRadius: ChatMetrics.bubbleRadius, style: .continuous))
    }

    /// A 4:3 photo up to 240 wide, with an optional caption under it.
    private func photo(url: URL, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RichPhoto(url: url, aspectRatio: 4 / 3)
                .accessibilityElement()
                .accessibilityLabel(caption ?? String(localized: "Photo"))
                .accessibilityAddTraits(.isImage)

            if let caption {
                Text(caption)
                    .font(.hotMess(.subheadline))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: 240)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: ChatMetrics.bubbleRadius, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 1, x: 0, y: 1)
    }

    /// An `accent-soft` card with a dashed `accent-ink` edge: "Special · until 11 PM",
    /// the title and the body. The room stops showing it at `endsAt`.
    private func special(title: String, text: String?, endsAt: Date?) -> some View {
        let shape = RoundedRectangle(cornerRadius: ChatMetrics.bubbleRadius, style: .continuous)

        return VStack(alignment: .leading, spacing: 2) {
            RichOverline(text: Self.specialOverline(endsAt: endsAt))
            RichTitleAndBody(title: title, text: text)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hotMessAccentSoft, in: shape)
        .overlay {
            shape.strokeBorder(Color.hotMessAccentInk, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
        }
    }

    /// A raised card: "Song request · Playing now" (or "Karaoke signup · On
    /// the list"), the request in words and the note to the host. It follows
    /// the request as the host works the queue: green while it's playing or
    /// the singer is on, faded once it's finished.
    private func request(_ request: ChatSongRequest, note: String?) -> some View {
        let shape = RoundedRectangle(cornerRadius: ChatMetrics.bubbleRadius, style: .continuous)
        let isUp = request.state == .up

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: request.kind == .song ? "music.note" : "music.mic")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isUp ? Color.hotMessSuccess : Color.hotMessAccentInk)
                .frame(width: 28, height: 28)
                .background(isUp ? Color.hotMessSuccessSoft : Color.hotMessAccentSoft, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                RichOverline(text: "\(request.label) · \(request.status)")
                RichTitleAndBody(title: request.headline, text: note)
            }
            .opacity(request.isFinished ? 0.6 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isUp ? Color.hotMessSuccessSoft : Color(.secondarySystemGroupedBackground), in: shape)
        .overlay {
            if isUp { shape.strokeBorder(Color.hotMessSuccess, lineWidth: 1.5) }
        }
    }

    /// "Special · until 11 PM", or "Special · until 11:30 PM"; "Special" with no end.
    static func specialOverline(endsAt: Date?, calendar: Calendar = .current) -> String {
        guard let endsAt else { return String(localized: "Special") }
        return String(localized: "Special · until \(ChatTime.clock(endsAt, calendar: calendar))")
    }
}

extension ChatTime {
    /// "11 PM", or "11:30 PM" when it isn't on the hour.
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let style = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .abbreviated))

        if calendar.component(.minute, from: date) == 0 {
            return date.formatted(style)
        }

        return date.formatted(style.minute(.twoDigits))
    }
}

// MARK: - Pieces

/// The small uppercase line over a rich card: "Announcement", "Special · until 11 PM".
private struct RichOverline: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.hotMess(fixedSize: 11, semibold: true))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Color.hotMessAccentInk)
            .lineLimit(1)
    }
}

private struct RichTitleAndBody: View {
    let title: String
    let text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !title.isEmpty {
                Text(title)
                    .font(.hotMess(.headline, semibold: true))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let text {
                Text(text)
                    .font(.hotMess(.subheadline))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
    }
}

/// A photo filling a box of the given shape, cropped to it.
private struct RichPhoto: View {
    let url: URL
    let aspectRatio: CGFloat

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { RemoteImage(url: url) }
            .clipped()
    }
}

// MARK: - From the API

extension VenueMessage {
    /// What to draw for a rich message, or `nil` to draw it as a text bubble
    /// (text, or a rich message missing what its kind needs, which then shows
    /// its summary).
    var richContent: ChatRichContent? {
        let written = written.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }

        switch kind {
        case .text:
            return nil
        case .announcement:
            guard let title, !title.isEmpty else { return nil }
            return .announcement(title: title, body: written, photoURL: photoURL, isPinned: isPinned)
        case .event:
            guard let event else { return nil }
            return .event(event, caption: written)
        case .photo:
            guard let photoURL else { return nil }
            return .photo(photoURL, caption: written)
        case .special:
            guard let title, !title.isEmpty else { return nil }
            return .special(title: title, body: written, endsAt: endsAt)
        case .request:
            guard let request else { return nil }
            return .request(request, note: written)
        case .prompt:
            // A PromptCard or the PromptBar, not a rich card (`promptCard`).
            return nil
        }
    }

    /// The PromptCard a quiet room got, or `nil`. A rotating prompt shows
    /// under the room's title instead, and a prompt the room sent without its
    /// question shows as its text.
    var promptCard: ChatPrompt? {
        guard kind == .prompt, let prompt, prompt.shownAs == .card else { return nil }
        return prompt
    }

    /// "Prompt" or "Trivia" for a text line that answers a prompt, by the
    /// prompt's kind where the room has it (`promptKinds`, by prompt ID).
    func promptLabel(promptKinds: [String: ChatPrompt.Kind] = [:]) -> String? {
        guard kind == .text, let promptID else { return nil }
        return promptKinds[promptID] == .trivia ? String(localized: "Trivia") : String(localized: "Prompt")
    }

    /// This message as a chat room draws it, for the reader `currentUserID`.
    ///
    /// - Parameters:
    ///   - friends: the reader's friends by ID. A friend's full name replaces
    ///     the short one rooms send to everyone.
    ///   - online: who is in the room now, when the room's roster is known.
    ///     Without it, the presence the API sent with the message (if any).
    ///   - rich: whether to draw rich messages and prompt cards as cards.
    ///     Peeks show their summary in a bubble instead.
    ///   - promptKinds: the room's prompts' kinds by ID, so an answer to
    ///     trivia is labelled "Trivia".
    func threadMessage(
        currentUserID: UUID?,
        friends: [UUID: Friend] = [:],
        online: Set<UUID>? = nil,
        reachable: Set<UUID> = [],
        rich: Bool = true,
        promptKinds: [String: ChatPrompt.Kind] = [:]
    ) -> ChatThreadMessage {
        let presence: PresenceState? = if isFromListing {
            nil
        } else if let online {
            online.contains(userID) ? .online : (reachable.contains(userID) ? .push : nil)
        } else {
            self.presence
        }

        // A bot says plain words (Glam's lines arrive as announcements under
        // its title), so it draws them as text, never as a card.
        let isBot = sender == .bot
        let botText = written.flatMap { $0.isEmpty ? nil : $0 } ?? body

        var line = ChatThreadMessage(
            id: id.uuidString,
            // A post as the venue, a listing, a bot or the audience groups
            // apart from the same person's own lines, and from each other.
            authorID: personID.map { "person:\($0.uuidString)" }
                ?? (isBot ? "bot:\(userID.uuidString)" : nil)
                ?? (isFromPlace ? "place:\(userID.uuidString)" : nil)
                ?? (isFromAudience ? "audience:\(userID.uuidString)" : userID.uuidString),
            authorName: isFromListing ? name : (friends[userID]?.name ?? name),
            avatarURL: avatarURL,
            text: isBot ? botText : body,
            sentAt: sentAt,
            isOwn: isOutgoing(for: currentUserID),
            presence: presence,
            role: role,
            isFromPlace: isFromPlace,
            isFromListing: isFromListing,
            isFromAudience: isFromAudience,
            rich: rich && !isBot ? richContent : nil,
            promptLabel: promptLabel(promptKinds: promptKinds),
            promptID: kind == .text ? promptID : nil,
            promptCard: rich ? promptCard : nil
        )
        line.sender = sender
        line.personID = personID
        line.personHasPage = personHasPage ?? true
        return line
    }
}

// MARK: - Previews

#Preview("Rich messages") {
    let start = Date(timeIntervalSince1970: 1_791_590_400)
    let messages: [ChatThreadMessage] = [
        ChatThreadMessage(
            id: "1", authorID: "place", authorName: "Neighbours", avatarURL: nil,
            text: "Announcement: Coat check closes at midnight", sentAt: start, isOwn: false,
            role: .venue, isFromPlace: true,
            rich: .announcement(
                title: "Coat check closes at midnight",
                body: "Grab your things before the late set. Lost and found is at the front door.",
                photoURL: nil,
                isPinned: true
            )
        ),
        ChatThreadMessage(
            id: "2", authorID: "aurora", authorName: "Aurora Borealis", avatarURL: nil,
            text: "Noted, thanks!", sentAt: start.addingTimeInterval(60), isOwn: false, presence: .online
        ),
        ChatThreadMessage(
            id: "3", authorID: "kiko", authorName: "Kiko M.", avatarURL: nil,
            text: "Next week I'm back with the disco set", sentAt: start.addingTimeInterval(180), isOwn: false,
            presence: .online, role: .host
        ),
        ChatThreadMessage(
            id: "4", authorID: "kiko", authorName: "Kiko M.", avatarURL: nil,
            text: "Shared an event: Sunset Social", sentAt: start.addingTimeInterval(200), isOwn: false,
            presence: .online, role: .host,
            rich: .event(SharedEvent(id: UUID(), name: "Sunset Social", startAt: start.addingTimeInterval(86_400 * 7)), caption: "Come through")
        ),
        ChatThreadMessage(
            id: "5", authorID: "place", authorName: "Neighbours", avatarURL: nil,
            text: "Special: Free coat check before 10", sentAt: start.addingTimeInterval(300), isOwn: false,
            role: .venue, isFromPlace: true,
            rich: .special(title: "Free coat check before 10", body: "At the front door.", endsAt: start.addingTimeInterval(7200))
        ),
        ChatThreadMessage(
            id: "6", authorID: "sam", authorName: "Sam O.", avatarURL: nil,
            text: "Be kind in here, folks.", sentAt: start.addingTimeInterval(360), isOwn: false, role: .staff
        ),
    ]

    NavigationStack {
        ChatThreadView(messages: messages, roomName: "Neighbours", pinned: messages[0])
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Neighbours")
            .navigationBarTitleDisplayMode(.inline)
    }
}
