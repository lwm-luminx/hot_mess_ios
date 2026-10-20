//
//  PairUpModel.swift
//  HotMess
//

import Foundation
import Observation

/// Pair me up at one venue: the user's state there, kept fresh while the
/// sheet is open, and what they do in it. Every action answers with the new
/// state, so the sheet moves on at once; polling picks up what the partner did.
@MainActor
@Observable
final class PairUpModel {
    private(set) var pairUp: VenuePairUp?
    private(set) var isLoaded = false
    private(set) var isBusy = false
    /// A refusal from the API, worded for the user.
    var errorMessage: String?
    /// What the last scan said, when it wasn't a meeting.
    var scanNotice: String?
    /// Set when a meeting is confirmed, for the "You met!" moment.
    private(set) var celebratedMatchID: UUID?

    let venueID: UUID
    private let api: HotMessAPI

    init(api: HotMessAPI, venueID: UUID) {
        self.api = api
        self.venueID = venueID
    }

    var state: PairUpState? { pairUp?.mine }
    var isHere: Bool { pairUp?.here == true }

    func load() async {
        do {
            pairUp = try await api.pairUp(venueID: venueID)
            noteMeeting()
        } catch is CancellationError {
        } catch {
            if !isLoaded { errorMessage = NowViewModel.message(for: error) }
        }
        isLoaded = true
    }

    /// Refreshes while the sheet is open: quickly while waiting on the other
    /// person, slowly otherwise.
    func poll() async {
        while !Task.isCancelled {
            await load()
            let waiting = state.map { $0.status == .searching || $0.status.isPaired } ?? false
            try? await Task.sleep(for: .seconds(waiting ? 3 : 15))
        }
    }

    func join(lookFor: String?) async {
        await perform { try await $0.joinPairUp(venueID: self.venueID, lookFor: lookFor) }
    }

    func accept() async {
        guard let id = state?.match?.id else { return }
        await perform { try await $0.acceptPairUp(matchID: id) }
    }

    func skip(partner: Bool) async {
        guard let id = state?.match?.id else { return }
        await perform { try await $0.skipPairUp(matchID: id, partner: partner) }
    }

    func cancel(_ match: PairUpMatch) async {
        await perform { try await $0.cancelPairUp(matchID: match.id) }
    }

    func leave() async {
        await perform { try await $0.leavePairUp(venueID: self.venueID) }
    }

    /// A fresh code to show; nil when the API refused one.
    func code() async -> String? {
        guard let id = state?.match?.id else { return nil }
        do {
            return try await api.showPairUpCode(matchID: id)
        } catch {
            errorMessage = NowViewModel.message(for: error)
            return nil
        }
    }

    func scan(_ code: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let scan = try await api.scanPairUpCode(venueID: venueID, code: code)
            if let mine = scan.pairUp { pairUp = VenuePairUp(here: isHere, mine: mine) }
            scanNotice = Self.notice(for: scan.outcome)
            noteMeeting()
        } catch {
            errorMessage = NowViewModel.message(for: error)
        }
    }

    func dismissCelebration() {
        celebratedMatchID = nil
    }

    /// Never the scanner's fault: each outcome says what to do next.
    static func notice(for outcome: PairUpScan.Outcome) -> String? {
        switch outcome {
        case .met: nil
        case .different: String(localized: "That's someone else's code, but here's a topic for the two of you.")
        case .used: String(localized: "That code was refreshed. Ask them to show it again.")
        case .ended: String(localized: "That pairing has ended.")
        case .own: String(localized: "That's your own code. Scan theirs instead.")
        case .unreadable: String(localized: "That isn't a Pair me up code. Try scanning again.")
        }
    }

    private var lastMetID: UUID?

    /// Celebrates each meeting once, whichever phone scanned.
    private func noteMeeting() {
        guard state?.status == .met, let match = state?.match, match.id != lastMetID else { return }
        lastMetID = match.id
        celebratedMatchID = match.id
    }

    private func perform(_ action: (HotMessAPI) async throws -> PairUpState?) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let mine = try await action(api)
            pairUp = VenuePairUp(here: isHere, mine: mine)
            noteMeeting()
        } catch {
            errorMessage = NowViewModel.message(for: error)
            await load()
        }
    }
}
