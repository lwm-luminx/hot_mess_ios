//
//  TribeViews.swift
//  HotMess
//

import SwiftUI

// Design system "Tribes and tags" (api/doc/design-system/TribesAndTags.md):
// the both glyph, the BothMark on an avatar, the BothLine after a name, and
// the picker's TribeChip and PickCounter. A match shows only between the two
// people who share a tribe, and only in chat; nothing here ever filters.

/// Two overlapping circles: "you both".
struct BothGlyph: View {
    var size: CGFloat = 10
    var color: Color = .hotMessOnAccent

    var body: some View {
        let ring = size * 0.62
        let line = max(1, size * 0.13)
        ZStack {
            Circle().stroke(color, lineWidth: line)
                .frame(width: ring, height: ring)
                .offset(x: -(size - ring) / 2)
            Circle().stroke(color, lineWidth: line)
                .frame(width: ring, height: ring)
                .offset(x: (size - ring) / 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The badge at an avatar's top right for someone who shares a tribe with
/// the user: the both glyph on an `accent` disc, ringed in the surface.
struct BothBadge: View {
    /// 16 on chat's small avatars, 18 on 40, 22 on the sheet's 64.
    var size: CGFloat = 16
    var surface: Color = Color(.secondarySystemGroupedBackground)

    var body: some View {
        BothGlyph(size: size * 0.62)
            .frame(width: size, height: size)
            .background(Color.hotMessAccent, in: .circle)
            .padding(2)
            .background(surface, in: .circle)
            .accessibilityHidden(true)
    }

    /// The badge for an avatar of `diameter`.
    static func size(for diameter: CGFloat) -> CGFloat {
        switch diameter {
        case ..<36: 13
        case ..<56: 18
        default: 22
        }
    }
}

extension View {
    /// The BothMark: a 2px `accent` ring outside a 2px gap, and the both badge
    /// at the top right, for someone who shares a tribe with the user. The
    /// presence dot keeps the bottom right. Draws nothing when `isOn` is false.
    func bothMark(_ isOn: Bool, diameter: CGFloat, surface: Color = Color(.secondarySystemGroupedBackground)) -> some View {
        modifier(BothMarkModifier(isOn: isOn, diameter: diameter, surface: surface))
    }
}

private struct BothMarkModifier: ViewModifier {
    let isOn: Bool
    let diameter: CGFloat
    let surface: Color

    func body(content: Content) -> some View {
        if isOn {
            // The ring and badge draw outside the avatar without moving it.
            content
                .padding(4)
                .overlay { Circle().strokeBorder(Color.hotMessAccent, lineWidth: 2) }
                .overlay(alignment: .topTrailing) {
                    BothBadge(size: BothBadge.size(for: diameter), surface: surface)
                        .offset(x: 2, y: -2)
                }
                .padding(-4)
        } else {
            content
        }
    }
}

/// The BothLine after a sender's name: the glyph and "You're both bears"
/// (or "You're both bears +1") in accent ink.
struct BothLine: View {
    let tribes: [SharedTribe]

    var body: some View {
        if let line = tribes.bothLine {
            HStack(spacing: 4) {
                BothGlyph(size: 11, color: .hotMessAccentInk)
                Text(line)
                    .font(.hotMess(.caption, semibold: true))
                    .foregroundStyle(Color.hotMessAccentInk)
                    .lineLimit(1)
            }
        }
    }
}

/// A tribe in the picker: off, on (`accent-soft`, with an × in "Your picks"),
/// or held back at the cap.
struct TribeChip: View {
    let name: String
    let isOn: Bool
    /// At the cap and not picked: dimmed, and says why when tapped.
    var isHeldBack = false
    /// "Your picks" chips carry an × that takes the tribe off.
    var showsRemove = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.hotMess(.subheadline, semibold: true))
                    .lineLimit(1)
                if showsRemove {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isOn ? Color.hotMessAccentInk : Color.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(isOn ? Color.hotMessAccentSoft : Color(.secondarySystemGroupedBackground), in: .capsule)
            .overlay {
                Capsule().strokeBorder(isOn ? Color.hotMessAccent : Color(.separator), lineWidth: 1)
            }
            .opacity(isHeldBack ? 0.45 : 1)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityHint(showsRemove ? String(localized: "Removes it from your picks") : "")
    }
}

/// "7 of 31 picked" beside a meter filled with `accent`.
struct PickCounter: View {
    let picked: Int
    let cap: Int

    var body: some View {
        HStack(spacing: 10) {
            Text(String(localized: "\(picked) of \(cap) picked"))
                .font(.hotMess(.subheadline, semibold: true))
                .monospacedDigit()
            ProgressView(value: Double(min(picked, cap)), total: Double(max(cap, 1)))
                .tint(Color.hotMessAccent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(picked) of \(cap) picked"))
    }
}

/// Lays chips out in rows, wrapping to the width it's given.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if next > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

#Preview("Both mark and line") {
    let tribes = [
        SharedTribe(id: "1", name: "Bear", bothPhrase: "You're both bears"),
        SharedTribe(id: "2", name: "Board games", bothPhrase: "You both play board games"),
    ]
    VStack(alignment: .leading, spacing: 24) {
        HStack(spacing: 24) {
            Avatar(url: nil, initials: "JK", size: 24, tintsInitials: true).bothMark(true, diameter: 24)
            Avatar(url: nil, initials: "JK", size: 40, tintsInitials: true).bothMark(true, diameter: 40)
            Avatar(url: nil, initials: "JK", size: 64, tintsInitials: true).bothMark(true, diameter: 64)
        }
        BothLine(tribes: tribes)
        BothLine(tribes: Array(tribes.prefix(1)))
        ChipFlow {
            TribeChip(name: "Bear", isOn: true, showsRemove: true) {}
            TribeChip(name: "Karaoke regular", isOn: false) {}
            TribeChip(name: "Board games", isOn: false, isHeldBack: true) {}
        }
        PickCounter(picked: 7, cap: 31)
    }
    .padding()
}
