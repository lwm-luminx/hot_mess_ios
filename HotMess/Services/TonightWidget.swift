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
    static let tonightWindow = TonightSnapshot.tonightWindow
    /// How far ahead the widget's rotating card looks for events.
    static let upcomingWindow: TimeInterval = 7 * 24 * 60 * 60
    /// The most events and Pings kept: enough to fill the large widget on the
    /// tallest phone.
    static let limit = 12

    /// From a freshly loaded Now: the next few events (the one they're at
    /// first, then their venue's and the rest of the city's, soonest first),
    /// who's on at their venue, and friends' Pings.
    static func update(from now: Now, at date: Date = .now) {
        let onNow = now.onNow.acts.first.map { $0.title ?? $0.person.name }
        let snapshot = TonightSnapshot(
            updatedAt: date,
            localeName: now.locale?.name,
            localeID: now.locale.map { $0.id.uuidString.lowercased() },
            venueName: now.venue?.name ?? now.event?.venue?.name,
            onNow: onNow,
            events: upcoming(now.events + now.cityEvents, leading: now.event, myPing: now.myPing, at: date),
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
        let pinged = pingedEventIDs(myPing, at: date)
        for index in snapshot.events.indices {
            snapshot.events[index].pinged = pinged.contains(snapshot.events[index].id)
        }
        save(snapshot.current(at: date))
    }

    /// From a background refresh of the city the widget shows, so its
    /// events keep coming while the app stays closed. Leaves a snapshot
    /// about a venue (the user was in one when Now last loaded) alone.
    static func update(events: [Event], in localeID: UUID, at date: Date = .now) {
        guard var snapshot = TonightStore.read(), snapshot.venueName == nil,
              snapshot.localeID == localeID.uuidString.lowercased()
        else { return }
        let pinged = Set(snapshot.events.filter(\.isPinged).map(\.id))
        snapshot.updatedAt = date
        snapshot.events = upcoming(events, myPing: nil, at: date).map { event in
            var event = event
            event.pinged = pinged.contains(event.id)
            return event
        }
        save(snapshot.current(at: date))
    }

    /// The events worth rotating through: `leading` (the one the user is
    /// at) first, then the rest that aren't over and start within
    /// ``upcomingWindow``, soonest first; at most ``limit``.
    static func upcoming(
        _ events: [Event], leading: Event? = nil, myPing: Ping?, at date: Date
    ) -> [TonightSnapshot.Event] {
        let end = date.addingTimeInterval(upcomingWindow)
        let pinged = pingedEventIDs(myPing, at: date)
        var seen = Set<UUID>()
        let rest = events
            .filter { $0.id != leading?.id && $0.startDate < end }
            .sorted { $0.startDate < $1.startDate }
        return ([leading].compactMap { $0 } + rest)
            .filter { seen.insert($0.id).inserted }
            .map { event in
                var entry = entry(for: event)
                entry.pinged = pinged.contains(entry.id)
                return entry
            }
            .filter { $0.isOn(at: date) }
            .prefix(limit)
            .map { $0 }
    }

    /// The events the user's own Ping names, by id.
    static func pingedEventIDs(_ myPing: Ping?, at date: Date) -> Set<String> {
        guard let myPing, myPing.expiresAt > date else { return [] }
        return Set(myPing.targets.compactMap { $0.event?.id.uuidString })
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
            url: URL(string: "hotmess://events/\(event.id.uuidString)"),
            address: event.venue?.address.flatMap { $0.isEmpty ? nil : $0 },
            going: event.rsvp == .attending
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
            },
            setGoing: { eventID, going in
                try await api.setRSVP(going ? .attending : .unsure, forEvent: eventID)
                await markEvent(eventID.uuidString) { $0.going = going }
            },
            pingEvent: { eventID in
                let current = try await api.pings()
                let ping = try await api.sendPing(
                    places: pingPlaces(adding: eventID, to: current.myPing),
                    note: current.myPing?.note,
                    localeID: TonightStore.read()?.localeID.flatMap(UUID.init(uuidString:)),
                    reach: current.myPing?.reach ?? .friends
                )
                await markEvent(eventID.uuidString) { $0.pinged = true }
                await refreshPings(PingsResponse(myPing: ping, friendPings: current.friendPings))
                await pingsChanged()
            }
        )
    }

    /// The user's Ping's picks with `eventID` added at the end (a new Ping
    /// names just the event). Keeps the order they picked in.
    static func pingPlaces(adding eventID: UUID, to myPing: Ping?) -> [PingPlace] {
        let places = myPing.map(\.places) ?? []
        return places.contains(.event(eventID)) ? places : places + [.event(eventID)]
    }

    /// Changes one event in the saved snapshot and redraws, so a button
    /// shows its result straight away.
    private static func markEvent(_ id: String, _ change: (inout TonightSnapshot.Event) -> Void) {
        guard let snapshot = TonightStore.read() else { return }
        save(snapshot.updating(event: id, change))
    }

    private static func refreshPings(_ pings: PingsResponse?) {
        guard let pings else { return }
        LiveActivities.sync(myPing: pings.myPing, friendPings: pings.friendPings)
        update(myPing: pings.myPing, friendPings: pings.friendPings)
    }
}
