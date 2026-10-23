//
//  HereNowStrip.swift
//  HotMess
//

import SwiftUI

/// Someone in a chat room now, or in the last 30 minutes, as the Here now
/// strip draws them.
struct HereNowPerson: Identifiable, Hashable, Sendable {
    let id: UUID
    /// A friend's full name, else the "First L." rooms send everyone. `nil`
    /// when the room hasn't said.
    let name: String?
    let avatarURL: URL?
    let isFriend: Bool
    /// `.online` while they're in the room; `.offline` (or `.push`, when a
    /// notification still reaches them) for someone who left in the last 30
    /// minutes and is still listed.
    var presence: PresenceState = .online
    /// The user themself, shown as "You", first in the strip.
    var isViewer = false

    /// In the room now, not only here recently.
    var isHere: Bool { presence == .online }

    var displayName: String {
        isViewer ? String(localized: "You") : name ?? String(localized: "Someone")
    }

    /// Under their avatar.
    var firstName: String {
        isViewer ? String(localized: "You") : name?.firstNameForDisplay ?? String(localized: "Someone")
    }

    /// What VoiceOver reads: "Aurora Bell, friend, here now", or "Sam K.,
    /// here recently" for someone who left lately.
    var accessibilityLabel: String {
        if isViewer { return String(localized: "You, here now") }
        return switch (isFriend, isHere) {
        case (true, true): String(localized: "\(displayName), friend, here now")
        case (false, true): String(localized: "\(displayName), here now")
        case (true, false): String(localized: "\(displayName), friend, here recently")
        case (false, false): String(localized: "\(displayName), here recently")
        }
    }

    /// The user first, then people here now before people here recently; in
    /// each, friends first, then everyone else, each by name. People with no
    /// name come last in their group.
    static func sorted(_ people: some Sequence<HereNowPerson>) -> [HereNowPerson] {
        people.sorted { lhs, rhs in
            if lhs.isViewer != rhs.isViewer { return lhs.isViewer }
            if lhs.isHere != rhs.isHere { return lhs.isHere }
            if lhs.isFriend != rhs.isFriend { return lhs.isFriend }

            switch (lhs.name, rhs.name) {
            case let (left?, right?):
                let order = left.localizedStandardCompare(right)
                if order != .orderedSame { return order == .orderedAscending }
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                break
            }

            // A stable order for people with the same name.
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

/// The venue whose room it is, first in the Here now strip: a venue is
/// always in its own room.
struct HereNowPlace: Hashable, Sendable {
    let name: String
    let photoURL: URL?
}

/// Who is in a chat room now, in one short row under the room's banner: the
/// count (when anyone else is here), the venue (always there in its own room), then everyone else,
/// friends first with an accent ring and a heart. A locale's room has no
/// venue, so draw it there only when someone else is here.
struct HereNowStrip: View {
    var place: HereNowPlace? = nil
    let people: [HereNowPerson]
    /// Report someone here, from their avatar's menu.
    var onReport: ((HereNowPerson) -> Void)? = nil
    /// Block someone here, which hides them at once.
    var onBlock: ((HereNowPerson) -> Void)? = nil
    /// Tapping someone (not the user): their profile sheet.
    var onSelect: ((HereNowPerson) -> Void)? = nil

    var body: some View {
        // One compact row: the count, then the faces. A horizontal scroll view
        // takes all the height it's offered, so it's held to its content's;
        // otherwise it splits the screen with the thread below it. The row is
        // a plain HStack: a LazyHStack reports no height of its own, so the
        // strip would collapse to nothing.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 10) {
                if hereCount > 0 {
                    Text(countLabel)
                        .font(.hotMess(.caption, semibold: true))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .accessibilityAddTraits(.isHeader)
                }

                if let place {
                    HereNowPlaceFace(place: place)
                }

                ForEach(people) { person in
                    // Nobody reports or blocks themself, or opens their own sheet.
                    face(person)
                        .contextMenu {
                            if !person.isViewer, onReport != nil || onBlock != nil {
                                safetyActions(for: person)
                            }
                        }
                        .accessibilityActions {
                            if !person.isViewer, onReport != nil || onBlock != nil {
                                safetyActions(for: person)
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            // Room for the friend badge, which sits above the ring.
            .padding(.top, 2)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.hereNow")
    }

    /// Only people in the room now count, the user included, not those here
    /// recently.
    private var hereCount: Int {
        people.filter(\.isHere).count
    }

    private var countLabel: String {
        String(localized: "\(hereCount) here now")
    }

    @ViewBuilder
    private func face(_ person: HereNowPerson) -> some View {
        if !person.isViewer, let onSelect {
            Button {
                onSelect(person)
            } label: {
                HereNowFace(person: person)
                    // At least 44pt to tap.
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(String(localized: "Shows their profile"))
        } else {
            HereNowFace(person: person)
        }
    }

    @ViewBuilder
    private func safetyActions(for person: HereNowPerson) -> some View {
        if let onReport {
            Button {
                onReport(person)
            } label: {
                Label(String(localized: "Report \(person.firstName)…"), systemImage: "exclamationmark.bubble")
            }
        }
        if let onBlock {
            Button(role: .destructive) {
                onBlock(person)
            } label: {
                Label(String(localized: "Block \(person.firstName)"), systemImage: "hand.raised")
            }
        }
    }
}

/// One person in the Here now strip: their avatar with the online dot (or,
/// for someone here recently, faded with the offline or push dot), and their
/// first name under it. A friend gets an accent ring and a heart badge, and
/// their name in accent ink.
struct HereNowFace: View {
    let person: HereNowPerson
    /// The surface behind the strip, for the rings around the dot and badge.
    var surface: Color = Color(.secondarySystemGroupedBackground)

    /// A TinyAvatar, as everywhere in chat.
    private static let avatarSize: CGFloat = ChatMetrics.avatarSize
    /// The gap between the photo and a friend's ring.
    private static let ringInset: CGFloat = 2
    /// A friend's `accent` ring, outside the gap.
    private static let ringWidth: CGFloat = 1.5

    var body: some View {
        VStack(spacing: 2) {
            Avatar(
                url: person.avatarURL,
                initials: person.name?.initialsForDisplay,
                size: Self.avatarSize,
                tintsInitials: true
            )
                .opacity(person.isHere ? 1 : 0.55)
                .padding(Self.ringInset + Self.ringWidth)
                .overlay {
                    if person.isFriend {
                        Circle().strokeBorder(Color.hotMessAccent, lineWidth: Self.ringWidth)
                    }
                }
                // Drawn over the ring, which would otherwise cover half of it.
                .overlay(alignment: .bottomTrailing) {
                    PresenceDot(state: person.presence, size: Avatar.presenceSize(for: Self.avatarSize), ringColor: surface, showsOffline: true)
                        .offset(x: -1, y: -1)
                }
                .overlay(alignment: .topTrailing) {
                    if person.isFriend {
                        FriendBadge(surface: surface)
                            .offset(x: 3, y: -3)
                    }
                }

            Text(person.firstName)
                .font(.hotMess(.caption2, semibold: person.isFriend))
                .foregroundStyle(person.isFriend ? Color.hotMessAccentInk : Color.secondary)
                .lineLimit(1)
                .frame(maxWidth: Self.avatarSize + (Self.ringInset + Self.ringWidth) * 2 + 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(person.accessibilityLabel)
    }
}

/// The venue in the Here now strip: its photo as a rounded square, so it
/// never looks like a person, and its name under it.
struct HereNowPlaceFace: View {
    let place: HereNowPlace

    /// The venue keeps its 28 (`size-avatar-sm`), close to `HereNowFace`'s
    /// avatar and ring, so the row lines up.
    private static let size: CGFloat = ChatMetrics.listingAvatarSize

    var body: some View {
        VStack(spacing: 2) {
            Avatar(url: place.photoURL, initials: place.name.initialsForDisplay, size: Self.size, isPlace: true)

            Text(place.name)
                .font(.hotMess(.caption2, semibold: true))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: Self.size + 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(place.name), the venue"))
    }
}

/// The small heart on a friend's avatar.
private struct FriendBadge: View {
    let surface: Color

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(Color.hotMessOnAccent)
            .frame(width: 13, height: 13)
            .background(Color.hotMessAccent, in: .circle)
            .padding(2)
            .background(surface, in: .circle)
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Here now") {
    let people = HereNowPerson.sorted([
        HereNowPerson(id: UUID(), name: "Sam K.", avatarURL: nil, isFriend: false),
        HereNowPerson(id: UUID(), name: "Aurora Bell", avatarURL: nil, isFriend: true),
        HereNowPerson(id: UUID(), name: "Jo P.", avatarURL: nil, isFriend: false),
        HereNowPerson(id: UUID(), name: "Alex Rivera", avatarURL: nil, isFriend: true),
        HereNowPerson(id: UUID(), name: nil, avatarURL: nil, isFriend: false),
        HereNowPerson(id: UUID(), name: "Billie J.", avatarURL: nil, isFriend: false, presence: .offline),
        HereNowPerson(id: UUID(), name: "Robin Lee", avatarURL: nil, isFriend: true, presence: .push),
    ])

    VStack(spacing: 0) {
        RoomBanner(kind: .range, roomName: "The Eagle")
        HereNowStrip(place: HereNowPlace(name: "The Eagle", photoURL: nil), people: people)
        PinnedBar(author: "The Eagle", title: "Doors open at 3") {}
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}
