//
//  LayoutRefreshPolicy.swift
//  HotMess
//

import CoreLocation
import Foundation

/// Decides when a screen's card layout is worth asking the server for again,
/// so a jittery GPS fix, a screen redrawing, or a slow server can't turn into
/// a stream of `Layout` queries.
///
/// A layout is due when it was never asked for, once the server's
/// `refreshAfter` has passed since the last good one, for another locale once
/// the last ask is `minimumLocaleSpacing` old, or for another beacon or a move
/// of at least `minimumDistance` once the last ask is `minimumSpacing` old.
/// After a failure nothing is due until a backoff passes, doubling from
/// `firstBackoff` up to `maximumBackoff`, however often the screen asks.
/// Only a person's own refresh (`force`) skips the wait.
struct LayoutRefreshPolicy: Sendable {
    typealias Instant = ContinuousClock.Instant

    /// What a layout was asked for.
    struct Request: Equatable, Sendable {
        var coordinates: Coordinates?
        var localeID: UUID?
    }

    var minimumDistance: CLLocationDistance = 150
    var minimumSpacing: Duration = .seconds(30)
    var minimumLocaleSpacing: Duration = .seconds(5)
    var minimumRefreshAfter: Duration = .seconds(15)
    var firstBackoff: Duration = .seconds(15)
    var maximumBackoff: Duration = .seconds(600)

    private(set) var lastAsked: Request?
    private(set) var lastAskedAt: Instant?
    /// When the server's order is next due (after a success) or may be tried again (after a failure).
    private(set) var dueAt: Instant?
    private(set) var failures = 0

    var isBackingOff: Bool { failures > 0 }

    func isDue(_ request: Request, at now: Instant, force: Bool = false) -> Bool {
        if force { return true }
        guard let lastAsked, let lastAskedAt else { return true }
        if let dueAt, now >= dueAt { return true }
        // A failure waits out its backoff wherever the device goes.
        if isBackingOff { return false }
        let sinceLastAsk = now - lastAskedAt
        // Another locale (a person picking a city) asks at once, but never more than once per
        // `minimumLocaleSpacing`, so a locale that flips back and forth can't stream asks.
        if lastAsked.localeID != request.localeID { return sinceLastAsk >= minimumLocaleSpacing }
        guard sinceLastAsk >= minimumSpacing else { return false }
        // Another beacon waits the same spacing as a move: ranging can hear the nearest beacon flip
        // between two venues every second, and each flip asked at once on every screen (2026-11-24).
        return changedPlace(from: lastAsked, to: request) || moved(from: lastAsked, to: request)
    }

    mutating func asked(_ request: Request, at now: Instant) {
        lastAsked = request
        lastAskedAt = now
    }

    /// The server answered; ask again once its `refreshAfter` (never under `minimumRefreshAfter`) has passed.
    mutating func succeeded(refreshAfter seconds: Int, at now: Instant) {
        failures = 0
        dueAt = now + max(.seconds(seconds), minimumRefreshAfter)
    }

    /// The ask failed or timed out; wait longer each time in a row.
    mutating func failed(at now: Instant) {
        failures += 1
        dueAt = now + backoff(after: failures)
    }

    /// The wait after `failures` failures in a row: `firstBackoff`, doubling, capped at `maximumBackoff`.
    func backoff(after failures: Int) -> Duration {
        guard failures > 0 else { return .zero }
        var wait = firstBackoff
        for _ in 1..<failures {
            wait = wait * 2
            if wait >= maximumBackoff { return maximumBackoff }
        }
        return min(wait, maximumBackoff)
    }

    /// Another beacon, or a position appearing or going away.
    private func changedPlace(from old: Request, to new: Request) -> Bool {
        switch (old.coordinates, new.coordinates) {
        case (nil, nil): return false
        case let (old?, new?): return old.beaconMajor != new.beaconMajor
        default: return true
        }
    }

    private func moved(from old: Request, to new: Request) -> Bool {
        guard let old = old.coordinates, let new = new.coordinates else { return false }
        return new.distance(from: old) >= minimumDistance
    }
}
