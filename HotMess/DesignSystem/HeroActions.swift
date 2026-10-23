//
//  HeroActions.swift
//  HotMess
//

import SwiftUI

/// A button or chip drawn on a hero photo: white on dark glass, so it reads
/// whatever the photo, or filled with the accent when it's selected.
struct HeroGlass: ViewModifier {
    var isSelected = false
    var fillsWidth = true

    func body(content: Content) -> some View {
        content
            .font(.hotMess(.subheadline, semibold: true))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(isSelected ? Color.hotMessOnAccent : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background {
                if isSelected {
                    Capsule().fill(Color.hotMessAccent)
                } else {
                    Capsule().fill(Color.hotMessGlass)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .contentShape(Capsule())
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    /// Styles a hero action. Use with `.buttonStyle(.plain)` on buttons and links.
    func heroGlass(selected: Bool = false, fillsWidth: Bool = true) -> some View {
        modifier(HeroGlass(isSelected: selected, fillsWidth: fillsWidth))
    }
}

/// The row of actions along the bottom of a hero, sharing its width.
struct HeroActionRow<Actions: View>: View {
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 10) {
            actions
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }
}

/// Overlapping faces for the people behind a line of hero text, such as an
/// event's hosts.
struct HeroFaces: View {
    struct Face: Identifiable {
        let id: UUID
        let name: String
        let url: URL?
    }

    let faces: [Face]
    var limit = 3
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: -7) {
            ForEach(Array(faces.prefix(limit).enumerated()), id: \.element.id) { index, face in
                Avatar(url: face.url, initials: face.name.initialsForDisplay, size: size)
                    .overlay { Circle().strokeBorder(Color.hotMessAvatarRing, lineWidth: 2) }
                    .zIndex(Double(limit - index))
            }
        }
        .accessibilityHidden(true)
    }
}

extension HeroFaces {
    init(people: [Person], limit: Int = 3) {
        self.init(faces: people.map { Face(id: $0.id, name: $0.name, url: $0.avatarURL) }, limit: limit)
    }

    init(friends: [Friend], limit: Int = 4) {
        self.init(faces: friends.map { Face(id: $0.id, name: $0.name, url: $0.avatarURL) }, limit: limit)
    }
}

extension Event {
    /// "Tonight · Drag Brunch at 11 AM", or "Fri · …" another day, for a hero's
    /// next-up line.
    var nextUpLine: String {
        let time = startDate.formatted(date: .omitted, time: .shortened)
        let day = Calendar.current.isDateInToday(startDate)
            ? String(localized: "Tonight")
            : startDate.formatted(.dateTime.weekday(.abbreviated))
        return String(localized: "\(day) · \(name) at \(time)")
    }
}
