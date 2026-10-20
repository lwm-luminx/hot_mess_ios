//
//  PairUp.swift
//  HotMess
//

import Foundation

/// Pair me up to chat at a venue (`venue.pairUp`): whether the user can opt
/// in now, and their pairing tonight. Nil on venues without it.
struct VenuePairUp: Decodable, Sendable, Equatable {
    /// The app places them at the venue, so they can opt in.
    let here: Bool
    /// Their Pair me up here tonight; nil until they opt in.
    let mine: PairUpState?
}

/// Where the user is in Pair me up at a venue tonight.
struct PairUpState: Decodable, Sendable, Equatable {
    let status: PairUpStatus
    /// The hint their partner sees once both accept.
    let lookFor: String?
    /// How many people they met tonight: the night's badge.
    let metCount: Int
    /// Their pairing. While searching, the last one when it ended.
    let match: PairUpMatch?
    /// A shared topic from a mistaken scan, while it lasts.
    let bonus: PairUpMatch?
}

enum PairUpStatus: String, Decodable, Sendable {
    case searching = "SEARCHING"
    case proposed = "PROPOSED"
    case waiting = "WAITING"
    case revealed = "REVEALED"
    case met = "MET"
    case left = "LEFT"

    /// A newer API's status reads as searching, so the sheet keeps polling.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PairUpStatus(rawValue: raw) ?? .searching
    }

    /// Paired and still going: the sheet shows the topic.
    var isPaired: Bool { self == .proposed || self == .waiting || self == .revealed }
}

/// A pairing as the user sees it.
struct PairUpMatch: Decodable, Sendable, Equatable, Identifiable {
    let id: UUID
    let accepted: Bool
    let partnerAccepted: Bool
    /// A fresh topic from scanning the wrong code: accepted, no code needed.
    let bonus: Bool
    let metAt: Date?
    /// SKIPPED, LEFT or BLOCKED once it ended; nil while it lasts.
    let endReason: String?
    let topic: PairUpTopic
    /// Who to look for, once both accepted; nil before and once either cancels.
    let partner: PairUpPartner?
}

struct PairUpTopic: Decodable, Sendable, Equatable {
    let key: String
    let text: String
}

/// Just enough to find someone in the room: never where they are.
struct PairUpPartner: Decodable, Sendable, Equatable {
    let id: UUID
    let name: String
    /// Tiny, served by the API only while the pairing lasts.
    let avatarUrl: URL?
    let lookFor: String?

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

/// What scanning a Pair me up code did.
struct PairUpScan: Decodable, Sendable {
    enum Outcome: String, Decodable, Sendable {
        case met = "MET"
        case different = "DIFFERENT"
        case used = "USED"
        case ended = "ENDED"
        case own = "OWN"
        case unreadable = "UNREADABLE"

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Outcome(rawValue: raw) ?? .unreadable
        }
    }

    let outcome: Outcome
    let match: PairUpMatch?
    let pairUp: PairUpState?
}
