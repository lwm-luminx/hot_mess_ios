//
//  HotMessActivity.swift
//  HotMess
//
//  Shared with the HotMessWidgets extension, which draws it on the Lock
//  Screen and in the Dynamic Island.
//

import ActivityKit
import Foundation

/// A Live Activity for something still going on tonight: a Ping the user sent
/// or joined (or a friend's they can join from it), or their Quickie at a
/// venue. It never names a Quickie partner or says where anyone is, since the
/// Lock Screen is visible to anyone nearby. Its buttons run the shared
/// intents (`WidgetIntents.swift`) in the app.
struct HotMessActivityAttributes: ActivityAttributes {
    enum Kind: String, Codable, Hashable, Sendable {
        case ping
        case quickie
    }

    struct ContentState: Codable, Hashable, Sendable {
        /// "Your Ping", "Sam's Ping", "Quickie at Purr".
        var title: String
        /// One line on where it stands: "3 people in", "Looking for someone".
        var status: String
        /// A word or two for the Dynamic Island's compact trailing side.
        var short: String
        /// When it ends, for a timer; nil when there's no set end.
        var endsAt: Date?
        /// The Quickie's topic while they're paired: what to talk about,
        /// never who with. Nil for a Ping. (Optional, like everything added
        /// after 2.8, so a running activity's older state still decodes.)
        var topic: String?
        /// The Quickie pairing the buttons act on.
        var matchID: String?
        /// The buttons to show, in order.
        var actions: [Action]?
        /// Where Chat goes: the Ping's circle chat, or the Quickie chat.
        var chatURL: URL?
    }

    /// A button on the activity.
    enum Action: String, Codable, Hashable, Sendable {
        /// "I'm in" on a friend's Ping (`JoinPingIntent`).
        case joinPing
        /// "I'm in" on the Quickie's topic (`AcceptQuickieIntent`).
        case acceptQuickie
        /// "New topic" (`NewQuickieTopicIntent`).
        case newTopic
        /// Opens `chatURL`.
        case chat
    }

    var kind: Kind
    /// The Ping's ID, or the venue's for a Quickie: which one this is.
    var key: String
    /// Where a tap goes (`hotmess://pings/<id>`, `hotmess://venues/<id>`).
    var url: URL?
}
