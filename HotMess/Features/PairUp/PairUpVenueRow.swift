//
//  PairUpVenueRow.swift
//  HotMess
//

import SwiftUI

/// The venue screen's way into Pair me up: shown where the venue has it and
/// the user is there (or already opted in tonight).
struct PairUpVenueRow: View {
    let pairUp: VenuePairUp
    let open: () -> Void
    /// After a meeting, starts the next quickie straight from the row rather
    /// than reopening the finished one.
    var goAgain: (() -> Void)?

    var body: some View {
        DetailSection(String(localized: "Meet someone")) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.hotMess(.subheadline, semibold: true))
                    Text(subtitle)
                        .font(.hotMess(.footnote))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button(action: status == .met ? (goAgain ?? open) : open) {
                    Text(buttonTitle).font(.hotMess(.subheadline, semibold: true))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("venue.pairUp")
            }
        }
    }

    private var status: PairUpStatus? {
        pairUp.mine.flatMap { $0.status == .left ? nil : $0.status }
    }

    private var headline: String {
        switch status {
        case .searching: String(localized: "Finding someone to chat with")
        case .proposed: String(localized: "You've got a match")
        case .waiting: String(localized: "Waiting for them to say yes")
        case .revealed: String(localized: "Go find each other")
        case .met: String(localized: "You met someone!")
        case .left, nil: String(localized: "Quickie")
        }
    }

    private var subtitle: String {
        switch status {
        case nil: String(localized: "Get paired with someone here and a topic to talk about.")
        case .met: String(localized: "Up for another quickie?")
        default: String(localized: "Open to see where you're at.")
        }
    }

    private var buttonTitle: String {
        switch status {
        case nil: String(localized: "Start")
        case .met: String(localized: "Go again")
        default: String(localized: "Open")
        }
    }
}
