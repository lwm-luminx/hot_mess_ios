//
//  VenueTriviaModel.swift
//  HotMess
//

import AudienceKit
import Foundation
import Observation

/// A venue's group trivia while the user is in its chat: the latest round,
/// from the SDK's show (`show(venueID:)`), for the TriviaRoundCard above the
/// composer. The whole room votes together on a "Myth or Legend" call; there
/// are only counts, never scores or names. It refreshes while the chat is open
/// (faster while a round takes votes) and when the venue posts, and keeps the
/// last round if a fetch fails. On an API without show control it stays empty.
@MainActor
@Observable
final class VenueTriviaModel {
    /// The round to show, if any: one taking votes, waiting on its answer, or
    /// revealed in the last few minutes.
    private(set) var round: TriviaRound?
    /// The server's reason a vote didn't count, for an alert.
    var voteError: String?

    /// How long a revealed round stays on the card.
    static let revealedFor: TimeInterval = 5 * 60

    private let api: HotMessAPI
    let venueID: UUID
    private var latest: TriviaRound?

    init(api: HotMessAPI, venueID: UUID) {
        self.api = api
        self.venueID = venueID
    }

    /// Refetches the latest round.
    func refresh(now: Date = .now) async {
        guard let show = try? await api.show(venueID: venueID) else { return }
        latest = show.trivia
        update(now: now)
    }

    /// Keeps refreshing until cancelled: every 10 seconds while a round takes
    /// votes, else every 30.
    func run() async {
        while !Task.isCancelled {
            await refresh()
            let pause: Duration = round?.voting == true ? .seconds(10) : .seconds(30)
            do { try await Task.sleep(for: pause) } catch { return }
        }
    }

    /// Votes for a choice, or changes the vote.
    func vote(_ choice: String) async {
        guard let round else { return }
        do {
            latest = try await api.voteTrivia(roundID: round.id, choice: choice)
            update(now: .now)
        } catch {
            voteError = error.localizedDescription
        }
    }

    /// Drops a round revealed more than `revealedFor` ago.
    func update(now: Date) {
        guard let latest else {
            round = nil
            return
        }
        if let revealedAt = latest.revealedAt, now.timeIntervalSince(revealedAt) > Self.revealedFor {
            round = nil
        } else {
            round = latest
        }
    }
}
