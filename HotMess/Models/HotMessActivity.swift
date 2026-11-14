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
/// or joined, or their Quickie at a venue. It never names a Quickie partner or
/// says where anyone is, since the Lock Screen is visible to anyone nearby.
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
    }

    var kind: Kind
    /// The Ping's ID, or the venue's for a Quickie: which one this is.
    var key: String
    /// Where a tap goes (`hotmess://pings/<id>`, `hotmess://venues/<id>`).
    var url: URL?
}
