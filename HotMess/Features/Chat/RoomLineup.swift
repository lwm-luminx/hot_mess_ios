//
//  RoomLineup.swift
//  HotMess
//

import AudienceKit
import Foundation

// Tonight's lineup in a venue's chat room (#391): the venue's lineup from the
// SDK (`VenueLineupModel`), joined to the presence the room sends for each
// person on it (`VenueChatViewModel.lineupPresence`), for the Here now strip,
// the "In this room" sheet and the Small talk peek on Now.

extension HereNowLineupFace {
    /// Tonight's lineup as the room shows it, without karaoke singers (they're
    /// guests): the host first, as the host row leads with them, then the
    /// act on now, the one up next, the rest still to come, and done acts
    /// last, each group in running order. A done host goes with the done
    /// acts. An intermission shows only while it's on.
    ///
    /// - Parameter presence: the room's lineup presence, by person ID
    ///   lowercased; `nil` when the room hasn't said, which draws no dots.
    static func faces(
        for lineup: VenueLineup,
        presence: [String: PresenceState]?,
        timeZone: TimeZone = .current
    ) -> [HereNowLineupFace] {
        let shown = lineup.acts.filter { $0.kind != .intermission || $0.state == .on }

        func rank(_ entry: AudienceKit.LineupEntry) -> Int {
            if entry.role == .host, entry.state != .done { return 0 }
            if entry.state == .on { return 1 }
            if entry.state == .done { return 4 }
            return entry.id == lineup.upNextID ? 2 : 3
        }

        return shown.enumerated()
            .sorted { lhs, rhs in
                let left = rank(lhs.element), right = rank(rhs.element)
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            .map { HereNowLineupFace(entry: $0.element, upNextID: lineup.upNextID, presence: presence, timeZone: timeZone) }
    }

    init(
        entry: AudienceKit.LineupEntry,
        upNextID: String?,
        presence: [String: PresenceState]?,
        timeZone: TimeZone = .current
    ) {
        let isIntermission = entry.kind == .intermission
        self.init(
            id: entry.id,
            name: entry.displayName,
            people: entry.people.prefix(2).map { Person(name: $0.name, avatarURL: $0.avatarUrl.flatMap(URL.init(string:))) },
            role: Role(entry.role),
            status: Self.status(of: entry, upNextID: upNextID),
            isIntermission: isIntermission,
            setTime: Self.setTime(of: entry, timeZone: timeZone),
            presence: isIntermission ? nil : Self.presence(of: entry, in: presence),
            personID: entry.personID
        )
    }

    /// On now, Up next or Done, as the lineup strip badges it.
    static func status(of entry: AudienceKit.LineupEntry, upNextID: String?) -> Status? {
        switch entry.state {
        case .on: .onNow
        case .done: .done
        default: entry.id == upNextID ? .upNext : nil
        }
    }

    /// The act's presence, rolled up over its people (a duet's two
    /// listings): in chat if any is, else reachable by push if any is, else
    /// offline. `nil` when the room hasn't said.
    static func presence(of entry: AudienceKit.LineupEntry, in presence: [String: PresenceState]?) -> PresenceState? {
        guard let presence else { return nil }
        let states = entry.people.compactMap { presence[$0.id.lowercased()] }
        if states.contains(.online) { return .online }
        if states.contains(.push) { return .push }
        return .offline
    }

    /// The set time, only for a hard start, as AudienceKitUI's lineup shows
    /// it: "8:00 PM", "8:00 PM – close", "8:00 PM – 9:00 PM".
    static func setTime(of entry: AudienceKit.LineupEntry, timeZone: TimeZone) -> String? {
        guard entry.startTiming == .hard, let start = entry.startsAt else { return nil }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        switch entry.endTiming {
        case .close:
            return "\(start.formatted(style)) – \(String(localized: "close"))"
        case .time:
            guard let end = entry.endsAt else { return start.formatted(style) }
            return "\(start.formatted(style)) – \(end.formatted(style))"
        default:
            return start.formatted(style)
        }
    }
}

extension HereNowLineupFace.Role {
    /// The lineup's word for a role, and its icon, as AudienceKitUI's
    /// `RoleLabel` has them; `nil` for an intermission or a role this build
    /// doesn't know.
    init?(_ role: AudienceKit.LineupEntry.Role?) {
        switch role {
        case .host: self.init(title: String(localized: "Host"), systemImage: "sparkles")
        case .dj: self.init(title: String(localized: "DJ"), systemImage: "headphones")
        case .performer: self.init(title: String(localized: "Performer"), systemImage: "theatermasks")
        case .mc: self.init(title: String(localized: "MC"), systemImage: "music.mic")
        case .singer: self.init(title: String(localized: "Singer"), systemImage: "music.mic")
        default: return nil
        }
    }
}

/// The line under the Small talk peek's faces on Now, at a venue: who's in
/// its room. "The Wildrose, 3 from tonight's lineup and Jordan · 23 here",
/// or without anyone from the lineup in chat, "The Wildrose · 23 here".
enum RoomSummary {
    /// - Parameters:
    ///   - venue: the venue's name; `nil` (a locale's room) says nothing.
    ///   - lineupInChat: how many acts on tonight's lineup are in chat now.
    ///   - friend: a friend in the room now, by first name.
    ///   - count: how many people are in the room now; `nil` while it isn't known.
    static func line(venue: String?, lineupInChat: Int, friend: String?, count: Int?) -> String? {
        guard let venue else { return nil }
        let who: String
        switch (lineupInChat, friend) {
        case (0, _):
            // Nothing to say beyond the venue without the count.
            guard count != nil else { return nil }
            who = venue
        case let (lineup, friend?):
            who = String(localized: "\(venue), \(lineup) from tonight's lineup and \(friend)")
        case let (lineup, nil):
            who = String(localized: "\(venue) and \(lineup) from tonight's lineup")
        }
        guard let count else { return who }
        return who + " · " + String(localized: "\(count) here")
    }
}
