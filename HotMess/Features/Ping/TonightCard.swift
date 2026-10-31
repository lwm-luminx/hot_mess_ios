//
//  TonightCard.swift
//  HotMess
//

import SwiftUI

/// "Did your plans change?": you've been at a venue your Ping doesn't name
/// for a while. The Ping moves only if you say so.
struct PlanChangePrompt: View {
    /// The venue you're at.
    let venueName: String
    /// What your Ping names now, "Drag Bingo · The Wildrose".
    let pingPlaces: String
    let isBusy: Bool
    let move: () -> Void
    let keep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Did your plans change?")
                    .font(.hotMess(.headline, semibold: true))
            } icon: {
                Image(systemName: "location.fill")
                    .foregroundStyle(Color.hotMessAccent)
            }
            .accessibilityAddTraits(.isHeader)

            Text("You're at \(venueName), but your ping says \(pingPlaces).")
                .font(.hotMess(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button(action: move) {
                    Text("Move my ping here")
                        .font(.hotMess(.subheadline, semibold: true))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("tonight.movePing")

                Button(action: keep) {
                    Text("Keep it")
                        .font(.hotMess(.subheadline, semibold: true))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("tonight.keepPing")
            }
            .disabled(isBusy)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: CardMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
                .strokeBorder(Color.hotMessAccent, lineWidth: 2)
        }
    }
}

/// No Ping running: one tap to start one where you are, or anywhere.
struct StartPingRow: View {
    /// The venue you're at, when Now places you at one.
    let venueName: String?
    let start: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Going out tonight?")
                    .font(.hotMess(.subheadline, semibold: true))
                Text(venueName.map { "Tell your friends you're at \($0)." } ?? "Tell your friends you want to go out.")
                    .font(.hotMess(.footnote))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: start) {
                Label(venueName == nil ? String(localized: "Ping") : String(localized: "Ping here"),
                      systemImage: "paperplane.fill")
                    .font(.hotMess(.subheadline, semibold: true))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("tonight.startPing")
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: CardMetrics.cornerRadius))
    }
}

/// Friends at the venue you're at, with a way to bring more.
struct FriendsHereRow: View {
    let friends: [Friend]
    let invite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            FriendFaces(friends: friends)

            VStack(alignment: .leading, spacing: 2) {
                Text(NowScreen.friendsHereLine(friends))
                    .font(.hotMess(.subheadline, semibold: true))
                Text(friends.map(\.firstName).formatted(.list(type: .and)))
                    .font(.hotMess(.footnote))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            Button(action: invite) {
                Label(String(localized: "Invite more"), systemImage: "person.badge.plus")
                    .font(.hotMess(.subheadline, semibold: true))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint(String(localized: "Text a link to people who aren't here yet"))
            .accessibilityIdentifier("tonight.inviteMore")
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: CardMetrics.cornerRadius))
    }
}

#Preview("Tonight") {
    let friends = [
        Friend(id: UUID(), name: "Sam Chatter", presence: .online),
        Friend(id: UUID(), name: "Alex Friend"),
    ]
    ScrollView {
        VStack(spacing: 12) {
            PlanChangePrompt(
                venueName: "Pony", pingPlaces: "Drag Bingo · The Wildrose", isBusy: false,
                move: {}, keep: {}
            )
            StartPingRow(venueName: "Pony", start: {})
            StartPingRow(venueName: nil, start: {})
            FriendsHereRow(friends: friends, invite: {})
        }
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}
