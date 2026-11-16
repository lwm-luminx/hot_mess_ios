//
//  LiveActivities.swift
//  HotMess
//

import ActivityKit
import Foundation

/// Keeps one Live Activity per kind on the Lock Screen while something is
/// open tonight: the Ping the user sent (or else the first one they joined),
/// and their Quickie while it's searching or paired. The app updates them
/// whenever it loads that state, and ends them once it's over. In the
/// background they keep their last state until it goes stale.
@MainActor
enum LiveActivities {
    private typealias Attributes = HotMessActivityAttributes

    /// Shows the open Ping, or ends the Ping activity when there is none.
    static func sync(myPing: Ping?, friendPings: [Ping], now: Date = .now) {
        let ping = [myPing].compactMap { $0 }.first { $0.expiresAt > now }
            ?? friendPings.first { $0.joined && $0.expiresAt > now }
        guard let ping else {
            end(.ping)
            return
        }
        let count = ping.joins.count
        let place = ping.targets.first?.name ?? ""
        let people = count == 1 ? String(localized: "1 person in") : String(localized: "\(count) people in")
        let state = Attributes.ContentState(
            title: ping.isMine ? String(localized: "Your Ping") : String(localized: "\(ping.user.firstName)'s Ping"),
            status: place.isEmpty ? people : "\(people) · \(place)",
            short: String(localized: "\(count) in"),
            endsAt: ping.expiresAt
        )
        show(.ping, key: ping.id, url: URL(string: "hotmess://pings/\(ping.id)"), state: state, staleDate: ping.expiresAt)
    }

    /// Shows the user's Quickie at a venue while it's open, or ends it.
    static func sync(quickie: PairUpState?, venueID: UUID, venueName: String?) {
        guard let quickie, let line = lines(for: quickie) else {
            end(.quickie, key: venueID.uuidString)
            return
        }
        let name = venueName?.isEmpty == false ? venueName : nil
        let state = Attributes.ContentState(
            title: name.map { String(localized: "Quickie at \($0)") } ?? String(localized: "Quickie"),
            status: line.status,
            short: line.short,
            endsAt: nil
        )
        show(.quickie, key: venueID.uuidString, url: URL(string: "hotmess://venues/\(venueID.uuidString)"),
             state: state, staleDate: Date.now.addingTimeInterval(6 * 60 * 60))
    }

    /// Ends every Hot Mess Live Activity, for signing out.
    static func endAll() {
        for activity in Activity<Attributes>.activities {
            endActivity(id: activity.id)
        }
    }

    /// What the activity says at each step. Nil once it's over (met, left).
    /// Never the partner's name: the Lock Screen is for anyone to see.
    static func lines(for state: PairUpState) -> (status: String, short: String)? {
        switch state.status {
        case .searching:
            (String(localized: "Looking for someone to pair you with"), String(localized: "Looking"))
        case .proposed:
            (String(localized: "We found someone. Open to see your topic"), String(localized: "Found"))
        case .waiting:
            (String(localized: "Waiting for them to say yes"), String(localized: "Waiting"))
        case .revealed:
            (String(localized: "You both said yes. Open to see who to look for"), String(localized: "Go!"))
        case .met, .left:
            nil
        }
    }

    private static func show(
        _ kind: Attributes.Kind, key: String, url: URL?, state: Attributes.ContentState, staleDate: Date?
    ) {
        let existing = Activity<Attributes>.activities.filter { $0.attributes.kind == kind }
        let content = ActivityContent(state: state, staleDate: staleDate)
        if let current = existing.first(where: { $0.attributes.key == key }) {
            for other in existing where other.id != current.id {
                endActivity(id: other.id)
            }
            guard current.content.state != state else { return }
            updateActivity(id: current.id, content: content)
            return
        }
        for other in existing {
            endActivity(id: other.id)
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activity.request(attributes: Attributes(kind: kind, key: key, url: url), content: content)
        } catch {
            Log.app.error("Live Activity failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func end(_ kind: Attributes.Kind, key: String? = nil) {
        for activity in Activity<Attributes>.activities
        where activity.attributes.kind == kind && (key == nil || activity.attributes.key == key) {
            endActivity(id: activity.id)
        }
    }

    // `Activity` isn't Sendable, so the tasks carry only its ID and look it up
    // again off the main actor.

    private nonisolated static func endActivity(id: String) {
        Task {
            guard let activity = Activity<Attributes>.activities.first(where: { $0.id == id }) else { return }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private nonisolated static func updateActivity(id: String, content: ActivityContent<Attributes.ContentState>) {
        Task {
            guard let activity = Activity<Attributes>.activities.first(where: { $0.id == id }) else { return }
            await activity.update(content)
        }
    }
}
