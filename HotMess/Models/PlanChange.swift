//
//  PlanChange.swift
//  HotMess
//

import Foundation

/// When to ask "Did your plans change?": your Ping names other places and
/// you've stayed at a venue it doesn't name long enough not to be walking
/// past. Asking is all it does. The Ping moves only when you say so.
struct PlanChangeCheck: Equatable, Sendable {
    /// How long you stay at a venue before Now asks, so walking past one
    /// (or the GPS drifting into the bar next door) doesn't.
    static let dwell: TimeInterval = 5 * 60

    /// The venue Now places you at, and since when.
    private(set) var arrival: Arrival?
    /// "<ping>:<venue>" pairs you already answered, so Now doesn't ask again.
    private(set) var answered: Set<String> = []

    struct Arrival: Equatable, Sendable {
        let venueID: UUID
        let since: Date
    }

    /// Notes where Now places you: the same venue keeps its arrival time, a
    /// new one starts the clock again, and none clears it.
    mutating func observe(venueID: UUID?, at date: Date) {
        guard let venueID else {
            arrival = nil
            return
        }
        if arrival?.venueID != venueID {
            arrival = Arrival(venueID: venueID, since: date)
        }
    }

    /// The venue to ask about for `ping`, or `nil`: no running Ping, an
    /// "anywhere" Ping (any venue fits it), a pick here already, not here
    /// long enough yet, or already answered.
    func venueToAsk(about ping: Ping?, at date: Date) -> UUID? {
        guard let ping, ping.isMine, ping.isActive(at: date), !ping.targets.isEmpty,
              let arrival, date.timeIntervalSince(arrival.since) >= Self.dwell,
              ping.targets(atVenue: arrival.venueID).isEmpty,
              !answered.contains(Self.key(ping.id, arrival.venueID)) else { return nil }
        return arrival.venueID
    }

    /// Remembers that you answered for `ping` at `venueID`, either way.
    mutating func answer(_ ping: Ping, at venueID: UUID) {
        answered.insert(Self.key(ping.id, venueID))
    }

    private static func key(_ pingID: String, _ venueID: UUID) -> String {
        "\(pingID):\(venueID.uuidString)"
    }
}
