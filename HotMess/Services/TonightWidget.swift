//
//  TonightWidget.swift
//  HotMess
//

import Foundation
import WidgetKit

/// Feeds the Tonight widget and runs the widget and Live Activity buttons.
///
/// The app writes a ``TonightSnapshot`` whenever Now loads and whenever the
/// Pings change (a button, a background refresh), then asks WidgetKit to
/// redraw. The widget never signs in or calls the API on its own.
@MainActor
enum TonightWidget {
    /// How far ahead counts as tonight.
    static let tonightWindow: TimeInterval = 12 * 60 * 60
    /// The most events and Pings kept: the large widget shows about this many.
    static let limit = 6

    /// From a freshly loaded Now: tonight's events where the user is, who's
    /// on at their venue, and friends' Pings.
    static func update(from now: Now, at date: Date = .now) {
        var events: [TonightSnapshot.Event] = []
        if let event = now.event { events.append(entry(for: event)) }
        let end = date.addingTimeInterval(tonightWindow)
        events += now.events
            .filter { $0.id != now.event?.id && $0.startDate < end }
            .map(entry(for:))
        let onNow = now.onNow.acts.first.map { $0.title ?? $0.person.name }
        let snapshot = TonightSnapshot(
            updatedAt: date,
            localeName: now.locale?.name,
            venueName: now.venue?.name ?? now.event?.venue?.name,
            onNow: onNow,
            events: Array(events.filter { $0.isOn(at: date) }.prefix(limit)),
            pings: pings(myPing: now.myPing, friendPings: now.friendPings, at: date)
        )
        save(snapshot)
    }

    /// From the Pings alone (after a button, or a background refresh),
    /// keeping the events the last Now left.
    static func update(myPing: Ping?, friendPings: [Ping], at date: Date = .now) {
        var snapshot = TonightStore.read() ?? .empty
        snapshot.updatedAt = date
        snapshot.pings = pings(myPing: myPing, friendPings: friendPings, at: date)
        save(snapshot.current(at: date))
    }

    /// Forgets everything, for signing out.
    static func clear() {
        TonightStore.clear()
        WidgetCenter.shared.reloadTimelines(ofKind: TonightStore.widgetKind)
    }

    /// The user's own Ping first, then Pings friends sent them (not ones seen
    /// only through someone in a circle), ones they're in before the rest,
    /// newest first.
    static func pings(myPing: Ping?, friendPings: [Ping], at date: Date) -> [TonightSnapshot.Ping] {
        let friends = friendPings
            .filter { !$0.isMine && $0.via == nil && $0.expiresAt > date }
            .sorted { ($0.joined ? 0 : 1, $1.createdAt) < ($1.joined ? 0 : 1, $0.createdAt) }
        let mine = [myPing].compactMap { $0 }.filter { $0.expiresAt > date }
        return (mine + friends).prefix(limit).map(entry(for:))
    }

    static func entry(for ping: Ping) -> TonightSnapshot.Ping {
        TonightSnapshot.Ping(
            id: ping.id,
            sender: ping.isMine ? String(localized: "You") : ping.user.firstName,
            place: ping.targets.first.map(\.name).flatMap { $0.isEmpty ? nil : $0 },
            people: ping.joins.map(\.user.firstName),
            joined: ping.joined,
            isMine: ping.isMine,
            expiresAt: ping.expiresAt,
            url: URL(string: "hotmess://pings/\(ping.id)")
        )
    }

    static func entry(for event: Event) -> TonightSnapshot.Event {
        TonightSnapshot.Event(
            id: event.id.uuidString,
            name: event.name,
            place: event.venue?.name,
            startsAt: event.startDate,
            endsAt: event.endDate,
            url: URL(string: "hotmess://events/\(event.id.uuidString)")
        )
    }

    private static func save(_ snapshot: TonightSnapshot) {
        // Unchanged apart from the time: no redraw.
        var previous = TonightStore.read()
        previous?.updatedAt = snapshot.updatedAt
        guard previous != snapshot else { return }
        guard TonightStore.write(snapshot) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: TonightStore.widgetKind)
    }

    // MARK: - Buttons

    /// What the widget and Live Activity buttons do, in the app. Each one
    /// refreshes the Live Activity and the widget with what the API answers.
    /// `pingsChanged` tells the open screens to reload the Pings.
    static func handlers(api: HotMessAPI, pingsChanged: @escaping @MainActor @Sendable () -> Void)
        -> WidgetActions.Handlers {
        WidgetActions.Handlers(
            joinPing: { pingID in
                _ = try await api.joinPing(pingID)
                let pings = try? await api.pings()
                await refreshPings(pings)
                await pingsChanged()
            },
            acceptQuickie: { venueID, matchID in
                let state = try await api.acceptPairUp(matchID: matchID)
                await LiveActivities.sync(quickie: state, venueID: venueID, venueName: nil)
            },
            newQuickieTopic: { venueID, matchID in
                let state = try await api.skipPairUp(matchID: matchID, partner: false)
                await LiveActivities.sync(quickie: state, venueID: venueID, venueName: nil)
            }
        )
    }

    private static func refreshPings(_ pings: PingsResponse?) {
        guard let pings else { return }
        LiveActivities.sync(myPing: pings.myPing, friendPings: pings.friendPings)
        update(myPing: pings.myPing, friendPings: pings.friendPings)
    }
}
