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
                Button(action: open) {
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
        case .met: String(localized: "You met someone tonight")
        case .left, nil: String(localized: "Pair me up to chat")
        }
    }

    private var subtitle: String {
        status == nil
            ? String(localized: "Get paired with someone here and a topic to talk about.")
            : String(localized: "Open to see where you're at.")
    }

    private var buttonTitle: String {
        status == nil ? String(localized: "Pair me up") : String(localized: "Open")
    }
}
