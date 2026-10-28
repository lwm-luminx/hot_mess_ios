//
//  ChatSenderMocks.swift
//  HotMess
//

import SwiftUI

// Preview mocks for the five chat sender types (handoff 2026-10-26, §5), for
// review before the API and the room models change. Nothing here ships: the
// types are fileprivate and only the previews below use them. Once the look is
// agreed, `ChatSender` replaces ChatThreadMessage's isFromPlace / isFromListing
// / isFromAudience / role flags, and these views fold into ChatViews.swift.
//
// The five, as the API would send them (a `Sender` interface with `kind`, `name`
// and `avatarUrl`, implemented by one type per kind):
// - System: the room itself ("Darcy is on stage"). No avatar, a centred line.
// - Bot: software with a name, like Glam (the disco ball). Its own art with no
//   border or fill, so it reads as app chrome, and a small bot mark where a
//   person's presence dot would be: bots never show presence.
// - Venue: the place. A squarer avatar, a little larger than people's.
// - Persona: a human posting as a listing (Ty posting as Anya), with a role
//   badge that opens the talent page. A circle with a ring, a little larger.
//   A host typed into a lineup with no page gets a host glyph and no link.
// - Member: anyone posting as themself. Today's avatar, with presence.

/// Who a chat line is from.
fileprivate enum ChatSender: Hashable {
    case system
    /// `image` is the bot's art (Glam's disco ball); without one it draws a glyph.
    case bot(name: String, image: String?)
    case venue(name: String, photoURL: URL?)
    /// `role` is the badge ("Host"); `hasPage` says whether it links anywhere.
    case persona(name: String, photoURL: URL?, role: String, hasPage: Bool)
    /// `staff` adds the Staff badge members with a role still get.
    case member(name: String, photoURL: URL?, presence: PresenceState?, staff: Bool = false)

    enum Kind: String, CaseIterable { case system, bot, venue, persona, member }

    var kind: Kind {
        switch self {
        case .system: .system
        case .bot: .bot
        case .venue: .venue
        case .persona: .persona
        case .member: .member
        }
    }

    var name: String? {
        switch self {
        case .system: nil
        case let .bot(name, _), let .venue(name, _): name
        case let .persona(name, _, _, _), let .member(name, _, _, _): name
        }
    }

    /// Venue and persona avatars draw a step up from members' and bots' 24.
    var avatarSize: CGFloat {
        switch self {
        case .venue, .persona: 30
        default: ChatMetrics.avatarSize
        }
    }

    /// Venue and persona lines are accountable humans speaking for a listing,
    /// so they keep today's tinted bubble. Bots and members don't.
    var tintsBubble: Bool {
        switch self {
        case .venue, .persona: true
        default: false
        }
    }
}

// MARK: - Avatar

fileprivate struct SenderAvatar: View {
    let sender: ChatSender

    var body: some View {
        let size = sender.avatarSize

        switch sender {
        case .system:
            EmptyView()
        case let .bot(_, image):
            // No border, no fill: the bot's own art (or a glyph) on the
            // transcript, like toolbar chrome.
            Group {
                if let image {
                    Image(image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.62, weight: .semibold))
                        .foregroundStyle(Color.hotMessAccent)
                }
            }
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                BotMark(size: Avatar.presenceSize(for: size) + 4)
                    .offset(x: 2, y: 2)
            }
        case let .venue(name, url):
            Avatar(url: url, initials: name.initialsForDisplay, size: size, isPlace: true)
        case let .persona(name, url, _, hasPage):
            Group {
                if hasPage {
                    Avatar(url: url, initials: name.initialsForDisplay, size: size, tintsInitials: true)
                } else {
                    // A lineup name with no page: a host glyph instead of a face.
                    Image(systemName: "music.mic")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(Color.hotMessAccentInk)
                        .frame(width: size, height: size)
                        .background(Color.hotMessAccentSoft, in: .circle)
                }
            }
            .padding(2)
            .overlay { Circle().strokeBorder(Color.hotMessAccent, lineWidth: 2) }
        case let .member(name, url, presence, _):
            Avatar(url: url, initials: name.initialsForDisplay, size: size, presence: presence, tintsInitials: true)
        }
    }
}

/// The bot mark on a bot's avatar, where a person's presence dot sits: a
/// white chip glyph on the accent, ringed off the art, so it never reads
/// as a presence dot.
fileprivate struct BotMark: View {
    let size: CGFloat
    var ringColor: Color = Color(.systemGroupedBackground)

    var body: some View {
        Image(systemName: "cpu")
            .font(.system(size: size * 0.66, weight: .bold))
            .foregroundStyle(Color.hotMessOnAccent)
            .frame(width: size, height: size)
            .background(Color.hotMessAccent, in: .circle)
            .background(ringColor, in: .circle.inset(by: -1.5))
            .accessibilityHidden(true)
    }
}

// MARK: - Badges

/// The word after a sender's name. A persona's badge opens their talent page.
fileprivate struct SenderBadge: View {
    let sender: ChatSender

    var body: some View {
        switch sender {
        case .bot:
            pill("Bot", foreground: .secondary, background: Color.hotMessControlFill)
        case .venue:
            pill("Venue", foreground: .hotMessOnAccent, background: .hotMessAccent)
        case let .persona(_, _, role, hasPage):
            if hasPage {
                Button {} label: {
                    HStack(spacing: 2) {
                        Text(role)
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                    }
                    .modifier(PillStyle(foreground: .hotMessAccentInk, background: .hotMessAccentSoft))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(role), view talent page")
            } else {
                pill(role, foreground: .hotMessAccentInk, background: .hotMessAccentSoft)
            }
        case let .member(_, _, _, staff) where staff:
            pill("Staff", foreground: .primary, background: .hotMessControlFill)
        default:
            EmptyView()
        }
    }

    private func pill(_ text: String, foreground: Color, background: Color) -> some View {
        Text(text).modifier(PillStyle(foreground: foreground, background: background))
    }
}

fileprivate struct PillStyle: ViewModifier {
    let foreground: Color
    let background: Color

    func body(content: Content) -> some View {
        content
            .font(.hotMess(fixedSize: 11, semibold: true))
            .tracking(0.2)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(minHeight: 16)
            .background(background, in: .capsule)
            .fixedSize()
    }
}

// MARK: - Line

fileprivate struct SenderLine: View {
    let sender: ChatSender
    let text: String
    var isOwn = false

    var body: some View {
        if sender.kind == .system {
            // The room speaking: no avatar, no bubble, centred like a divider.
            Text(text)
                .font(.hotMess(.caption, semibold: true))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                if !isOwn { SenderAvatar(sender: sender) }

                VStack(alignment: isOwn ? .trailing : .leading, spacing: 2) {
                    if !isOwn {
                        HStack(spacing: 6) {
                            if let name = sender.name {
                                Text(name)
                                    .font(.hotMess(.caption, semibold: true))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            SenderBadge(sender: sender)
                        }
                        .padding(.leading, 12)
                    }

                    if sender.kind == .bot {
                        // A bot's line has no fill and no shadow: it sits on the
                        // transcript like the app's own words, never like a person.
                        Text(text)
                            .font(.hotMess(.subheadline))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 2)
                    } else {
                        ChatBubble(text: text, isOwn: isOwn, isRole: sender.tintsBubble)
                    }
                }
                .frame(maxWidth: ChatMetrics.bubbleMaxWidth, alignment: isOwn ? .trailing : .leading)
            }
            .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
        }
    }
}

// MARK: - Preview data

fileprivate enum SenderMockData {
    static let glam = ChatSender.bot(name: "Glam", image: "GlamAvatar")
    /// A bot with no art yet.
    static let plainBot = ChatSender.bot(name: "Door bot", image: nil)
    static let venue = ChatSender.venue(name: "The Pax", photoURL: nil)
    static let anya = ChatSender.persona(name: "Anya", photoURL: nil, role: "Host", hasPage: true)
    static let darcy = ChatSender.persona(name: "Darcy", photoURL: nil, role: "Host", hasPage: false)
    static let sam = ChatSender.member(name: "Sam R.", photoURL: nil, presence: .online)
    static let jo = ChatSender.member(name: "Jo K.", photoURL: nil, presence: .push)
    static let staff = ChatSender.member(name: "Ty M.", photoURL: nil, presence: nil, staff: true)
    static let me = ChatSender.member(name: "Me", photoURL: nil, presence: nil)

    /// One of each, labelled with its kind.
    static let gallery: [(String, ChatSender, String)] = [
        ("System", .system, "Darcy and Anya are on stage"),
        ("Bot", glam, "Welcome in! Signups for the next round open at 10."),
        ("Bot, no art", plainBot, "The line is about 10 minutes right now."),
        ("Venue", venue, "Happy hour runs till 9 tonight."),
        ("Persona", anya, "Who's ready to sing? Put your name down!"),
        ("Persona, no page", darcy, "Next up: Jo with Dancing Queen"),
        ("Member", sam, "Saving the booth by the stage"),
        ("Member, staff", staff, "Coat check is by the back door"),
    ]

    /// A karaoke night with all five talking.
    static let thread: [(ChatSender, String, Bool)] = [
        (.system, "Karaoke with Darcy and Anya started at 9:00 PM", false),
        (glam, "Hi all, I'm Glam, the room's bot. Be kind and keep it about the night.", false),
        (anya, "We're live! Signups are open, tap + under the lineup.", false),
        (sam, "Saving the booth by the stage", false),
        (jo, "Put me down for Dancing Queen", false),
        (me, "On my way", true),
        (darcy, "Jo, you're up after this one", false),
        (venue, "Two-for-one wings till 10.", false),
        (.system, "Darcy pinned an announcement", false),
    ]
}

// MARK: - Previews

#Preview("Sender types") {
    ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(SenderMockData.gallery.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0.uppercased())
                        .font(.hotMess(fixedSize: 10, semibold: true))
                        .tracking(0.6)
                        .foregroundStyle(.tertiary)
                    SenderLine(sender: item.1, text: item.2)
                }
            }
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Thread, light") {
    SenderMockThread()
}

#Preview("Thread, dark") {
    SenderMockThread()
        .preferredColorScheme(.dark)
}

#Preview("Avatars") {
    HStack(alignment: .bottom, spacing: 18) {
        ForEach(ChatSender.Kind.allCases, id: \.self) { kind in
            VStack(spacing: 6) {
                switch kind {
                case .system:
                    Image(systemName: "minus").foregroundStyle(.quaternary).frame(height: 24)
                case .bot: SenderAvatar(sender: SenderMockData.glam)
                case .venue: SenderAvatar(sender: SenderMockData.venue)
                case .persona: SenderAvatar(sender: SenderMockData.anya)
                case .member: SenderAvatar(sender: SenderMockData.sam)
                }
                Text(kind.rawValue.capitalized)
                    .font(.hotMess(.caption2))
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding()
    .background(Color(.secondarySystemGroupedBackground))
}

fileprivate struct SenderMockThread: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(SenderMockData.thread.enumerated()), id: \.offset) { _, line in
                        SenderLine(sender: line.0, text: line.1, isOwn: line.2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("The Pax")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
