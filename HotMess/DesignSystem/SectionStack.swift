//
//  SectionStack.swift
//  HotMess
//

import SwiftUI

/// A page's sections, top to bottom and `spacing` apart, like `VStack(spacing:)`, except that a section drawing
/// nothing (no height) takes no spacing. The sections that load on their own (``NewsSection``, ``PostsSection``,
/// ``PhotosSection``) are always there, so their task runs, but are empty until they have something to show; in a
/// `VStack` each empty one would leave an extra gap.
struct SectionStack: Layout {
    var spacing: CGFloat = 24

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
        let shown = sizes.filter { $0.height > 0 }
        let height = shown.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(shown.count - 1, 0))
        return CGSize(width: proposal.width ?? sizes.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        var placedAny = false
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if size.height > 0 {
                if placedAny { y += spacing }
                placedAny = true
            }
            subview.place(at: CGPoint(x: bounds.midX, y: y), anchor: .top,
                          proposal: ProposedViewSize(width: bounds.width, height: size.height))
            y += size.height
        }
    }
}
