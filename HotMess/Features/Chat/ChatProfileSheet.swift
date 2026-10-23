//
//  ChatProfileSheet.swift
//  HotMess
//

import SwiftUI

/// Someone in a chat room, as their profile sheet shows them: whoever the
/// reader tapped, from a message or the Here now strip.
struct ChatProfile: Identifiable, Hashable, Sendable {
    let id: UUID
    /// A friend's full name, else the "First L." rooms send everyone.
    let name: String?
    /// The small chat copy of their photo; chat never has a bigger one.
    let avatarURL: URL?
    /// The message the sheet opened from, which Report reports. `nil` from
    /// the Here now strip, which reports the person.
    var message: ChatThreadMessage? = nil

    var displayName: String {
        name.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Someone")
    }
}

/// Where the reader stands with someone, for the sheet's second button.
enum ChatFriendState: Hashable, Sendable {
    case notFriends
    /// Asked, this session, and not answered yet.
    case requested
    case friends
}

/// The sheet that opens from someone's avatar or name in chat (design system
/// "Tapping someone"): the same 24 TinyAvatar the room shows, their name and
/// whether they're in chat now, a note on why photos stay small, then Ping,
/// Add friend, and quieter Mute in this chat, Report and Block. There's no
/// bigger photo, here or anywhere in chat.
struct ChatProfileSheet: View {
    let profile: ChatProfile
    /// In the room now: the green dot and "In chat now".
    let isOnline: Bool
    let friendState: ChatFriendState
    var isSendingFriendRequest = false
    let isMuted: Bool
    let onPing: () -> Void
    let onAddFriend: () -> Void
    let onToggleMute: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            note
            mainButtons
            quietButtons
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(profile.displayName)
        .accessibilityIdentifier("chat.profileSheet")
    }

    // MARK: - Pieces

    /// The avatar, the name, and "In chat now" while they are.
    private var header: some View {
        HStack(spacing: 12) {
            ProfileAvatar(profile: profile, isOnline: isOnline, isFriend: friendState == .friends)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.hotMess(.headline, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)

                // "· Here since 8:40pm" waits on a join time from the API.
                if isOnline {
                    Text("In chat now")
                        .font(.hotMess(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var note: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Photos stay small in chat, for everyone. The best way to see who's who is to say hi in person.")
                .font(.hotMess(.footnote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.hotMessSurfaceSunken, in: .rect(cornerRadius: HotMessRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Ping and Add friend, two equal buttons.
    private var mainButtons: some View {
        HStack(spacing: 8) {
            Button(action: onPing) {
                Text("Ping")
            }
            .buttonStyle(ProfileSheetButtonStyle(isProminent: true))
            .accessibilityHint(String(localized: "Tells your friends where you are"))
            .accessibilityIdentifier("chat.profile.ping")

            friendButton
        }
    }

    @ViewBuilder
    private var friendButton: some View {
        switch friendState {
        case .friends:
            Button {} label: {
                Text("Friends")
            }
            .buttonStyle(ProfileSheetButtonStyle(isProminent: false))
            .disabled(true)
            .accessibilityLabel(String(localized: "Friends already"))
            .accessibilityIdentifier("chat.profile.friends")
        case .requested:
            Button {} label: {
                Text("Requested")
            }
            .buttonStyle(ProfileSheetButtonStyle(isProminent: false))
            .disabled(true)
            .accessibilityLabel(String(localized: "Friend request sent"))
            .accessibilityIdentifier("chat.profile.requested")
        case .notFriends:
            Button(action: onAddFriend) {
                if isSendingFriendRequest {
                    ProgressView()
                } else {
                    Text("Add friend")
                }
            }
            .buttonStyle(ProfileSheetButtonStyle(isProminent: false))
            .disabled(isSendingFriendRequest)
            .accessibilityLabel(String(localized: "Add \(profile.displayName) as a friend"))
            .accessibilityIdentifier("chat.profile.addFriend")
        }
    }

    /// "Mute in this chat" (or "Unmute in this chat"), Report and Block.
    private var quietButtons: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)

            QuietSheetButton(
                title: isMuted ? String(localized: "Unmute in this chat") : String(localized: "Mute in this chat"),
                color: .hotMessAccentInk,
                action: onToggleMute
            )
            .accessibilityHint(isMuted
                ? String(localized: "Shows their messages in this chat again")
                : String(localized: "Hides their messages in this chat, on this phone only"))
            .accessibilityIdentifier("chat.profile.mute")

            QuietSheetButton(title: String(localized: "Report"), color: .red, action: onReport)
                .accessibilityLabel(String(localized: "Report \(profile.displayName)"))
                .accessibilityIdentifier("chat.profile.report")

            QuietSheetButton(title: String(localized: "Block"), color: .red, action: onBlock)
                .accessibilityLabel(String(localized: "Block \(profile.displayName)"))
                .accessibilityIdentifier("chat.profile.block")

            Spacer(minLength: 0)
        }
    }
}

/// The TinyAvatar at the chat size, with the green dot while they're in the
/// room, and a friend's accent ring as the Here now strip draws it.
private struct ProfileAvatar: View {
    let profile: ChatProfile
    let isOnline: Bool
    let isFriend: Bool

    private static let size: CGFloat = ChatMetrics.avatarSize
    private static let ringInset: CGFloat = 2
    private static let ringWidth: CGFloat = 1.5

    var body: some View {
        Avatar(
            url: profile.avatarURL,
            initials: profile.name?.initialsForDisplay,
            size: Self.size,
            tintsInitials: true
        )
        .padding(Self.ringInset + Self.ringWidth)
        .overlay {
            if isFriend {
                Circle().strokeBorder(Color.hotMessAccent, lineWidth: Self.ringWidth)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isOnline {
                PresenceDot(state: .online, size: Avatar.presenceSize(for: Self.size), ringColor: Color(.systemBackground))
                    .offset(x: -1, y: -1)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Ping and Add friend: 44 tall, sharing the row equally. Prominent is the
/// accent; the other a control fill.
private struct ProfileSheetButtonStyle: ButtonStyle {
    let isProminent: Bool

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hotMess(.subheadline, semibold: true))
            .foregroundStyle(isProminent ? Color.hotMessOnAccent : Color.primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                isProminent ? Color.hotMessAccent : Color.hotMessControlFill,
                in: .rect(cornerRadius: HotMessRadius.md, style: .continuous)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
            .contentShape(.rect)
    }
}

/// A quiet text button in the sheet's last row, 44 tall.
private struct QuietSheetButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.hotMess(.footnote, semibold: true))
                .foregroundStyle(color)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Profile sheet") {
    Color(.systemGroupedBackground)
        .sheet(isPresented: .constant(true)) {
            ChatProfileSheet(
                profile: ChatProfile(id: UUID(), name: "Sam K.", avatarURL: nil),
                isOnline: true,
                friendState: .notFriends,
                isMuted: false,
                onPing: {},
                onAddFriend: {},
                onToggleMute: {},
                onReport: {},
                onBlock: {}
            )
        }
}
