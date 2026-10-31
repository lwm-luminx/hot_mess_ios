//
//  NowViewModel.swift
//  HotMess
//

import Foundation
import Observation
import os

@MainActor
@Observable
final class NowViewModel {
    private(set) var state: LoadState<Now> = .idle

    private let api: HotMessAPI
    private let friends: FriendDirectory?

    init(api: HotMessAPI, friends: FriendDirectory? = nil) {
        self.api = api
        self.friends = friends
    }

    /// Loads what's happening where the user is. The position report behind
    /// it is shared with everything else that reports the position, so a new
    /// fix nearby or coming back to the tab reuses a recent one; pass
    /// `sentAfter` to insist on one sent since then.
    func load(from location: LocationProvider, sentAfter: Date? = nil) async {
        if state.value == nil { state = .loading }

        do {
            var now = try await location.now(sentAfter: sentAfter)
            if now == nil {
                // No position yet: Pings don't depend on one.
                now = try await api.now(near: nil)
            }
            guard let now else { return }
            friends?.remember(now)
            state = .loaded(now)
            planCheck.observe(venueID: now.venues == nil ? now.venue?.id : nil, at: .now)
        } catch is CancellationError {
            // The view went away; leave whatever was on screen alone.
        } catch {
            // A refresh that fails keeps what's on screen; Now reloads again
            // within a minute.
            guard state.value == nil else {
                Log.network.error("Now refresh failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            state = LoadState(catching: error)
        }
    }

    // MARK: - Pings

    /// The Pings with a join, leave or end in flight.
    private(set) var busyPingIDs: Set<String> = []
    var pingError: String?

    /// "I'm in" on `target`, or on the whole Ping when it's `nil`.
    func join(_ ping: Ping, target: PingTarget?) async {
        await update(ping) { try await $0.joinPing(ping.id, targetID: target?.id) }
    }

    func leave(_ ping: Ping) async {
        await update(ping) { try await $0.leavePing(ping.id) }
    }

    /// Whether to ask "Did your plans change?", and where you've been.
    private(set) var planCheck = PlanChangeCheck()

    /// The venue to ask "Did your plans change?" about, if any.
    var planChangeVenue: Venue? {
        guard let now = state.value, let venueID = planCheck.venueToAsk(about: now.myPing, at: .now) else { return nil }
        return now.venue?.id == venueID ? now.venue : nil
    }

    /// "Yes, I'm here now": the user's Ping picks this venue (tonight's
    /// event here, when one is on) instead of its old picks. Keeps the note
    /// and who can see it; whoever was in on an old pick stays in on the
    /// Ping as a whole.
    func movePing(to venue: Venue, localeID: UUID?) async {
        guard let now = state.value, let ping = now.myPing else { return }
        planCheck.answer(ping, at: venue.id)
        var place = PingPlace.venue(venue.id)
        if let event = now.event, event.venue?.id == venue.id { place = .event(event.id) }
        await update(ping) {
            try await $0.sendPing(places: [place], note: ping.note, localeID: localeID, reach: ping.reach)
        }
    }

    /// "No, keep my ping": the Ping stays as it is, and Now stops asking
    /// about this venue.
    func keepPing(at venue: Venue) {
        guard let ping = state.value?.myPing else { return }
        planCheck.answer(ping, at: venue.id)
    }

    func endMyPing() async {
        guard let ping = state.value?.myPing else { return }
        busyPingIDs.insert(ping.id)
        defer { busyPingIDs.remove(ping.id) }

        do {
            try await api.endPing()
            if let now = state.value { state = .loaded(now.removingMyPing()) }
        } catch {
            pingError = Self.message(for: error)
        }
    }

    /// Shows a Ping the send sheet just sent or edited.
    func show(_ ping: Ping) {
        guard let now = state.value else { return }
        state = .loaded(now.replacing(ping))
    }

    private func update(_ ping: Ping, _ action: (HotMessAPI) async throws -> Ping) async {
        guard !busyPingIDs.contains(ping.id) else { return }
        busyPingIDs.insert(ping.id)
        defer { busyPingIDs.remove(ping.id) }

        do {
            let updated = try await action(api)
            if let now = state.value { state = .loaded(now.replacing(updated)) }
        } catch {
            pingError = Self.message(for: error)
        }
    }

    static func message(for error: any Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
