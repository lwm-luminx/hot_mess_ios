//
//  Suggestion.swift
//  HotMess
//

import AudienceKit
import Foundation

/// What a member can suggest about the audience's listings (the API's
/// `SubmissionKind`). A person checks every suggestion before anything
/// changes; see the API's doc/CONTRIBUTIONS.md.
enum SuggestionKind: String, Codable, Hashable, Sendable {
    case missingVenue = "MISSING_VENUE"
    case missingEvent = "MISSING_EVENT"
    case correction = "CORRECTION"
    case closed = "CLOSED"
    case tagSuggestion = "TAG_SUGGESTION"
    case localRulesCorrection = "LOCAL_RULES_CORRECTION"
    case talentLink = "TALENT_LINK"

    /// Unknown kinds a newer API adds read as a correction.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SuggestionKind(rawValue: raw) ?? .correction
    }

    var title: String {
        switch self {
        case .missingVenue: String(localized: "New venue")
        case .missingEvent: String(localized: "New event")
        case .correction: String(localized: "Fix")
        case .closed: String(localized: "Closed for good")
        case .tagSuggestion: String(localized: "Tag")
        case .localRulesCorrection: String(localized: "Local rules")
        case .talentLink: String(localized: "Performer")
        }
    }
}

/// Where a suggestion is (the API's `SubmissionStatus`), as the member sees
/// it: never whether the venue was asked.
enum SuggestionStatus: String, Codable, Hashable, Sendable {
    case submitted = "SUBMITTED"
    case researching = "RESEARCHING"
    case inReview = "IN_REVIEW"
    case needsVenue = "NEEDS_VENUE"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case merged = "MERGED"

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SuggestionStatus(rawValue: raw) ?? .submitted
    }
}

/// One of the member's own suggestions, for "Your suggestions".
struct SuggestionSummary: Decodable, Hashable, Sendable, Identifiable {
    struct Listing: Decodable, Hashable, Sendable {
        let id: String
        let name: String?
    }

    struct Decision: Decodable, Hashable, Sendable {
        let action: String
        let reason: String?
    }

    let id: String
    let kind: SuggestionKind
    let status: SuggestionStatus
    let reporterCount: Int
    let proposed: [String: GraphQLValue]
    let createdAt: Date
    let venue: Listing?
    let event: Listing?
    let decisions: [Decision]

    /// What it's about: the listing, or the name it proposed.
    var title: String {
        var proposedName: String?
        if case let .string(name)? = proposed["name"] { proposedName = name }
        let name: String? = switch kind {
        case .missingVenue: venue?.name ?? proposedName
        case .missingEvent: event?.name ?? proposedName
        default: event?.name ?? venue?.name
        }
        return name ?? kind.title
    }

    /// The badge: "Being checked", "Added", "Updated", "Closed" or "Not changed".
    var badge: String {
        switch status {
        case .submitted, .researching, .inReview, .needsVenue, .merged:
            String(localized: "Being checked")
        case .approved:
            switch kind {
            case .missingVenue, .missingEvent: String(localized: "Added")
            case .closed: String(localized: "Closed")
            default: String(localized: "Updated")
            }
        case .rejected:
            String(localized: "Not changed")
        }
    }

    /// The reviewer's reason, on a rejected suggestion.
    var rejectionReason: String? {
        guard status == .rejected else { return nil }
        return decisions.last { $0.action == "REJECT" }?.reason ?? decisions.last?.reason
    }

    /// An added venue or event to open.
    var addedRoute: AppRoute? {
        guard status == .approved else { return nil }
        switch kind {
        case .missingVenue: return venue.flatMap { UUID(uuidString: $0.id) }.map(AppRoute.venue)
        case .missingEvent: return event.flatMap { UUID(uuidString: $0.id) }.map(AppRoute.event)
        default: return nil
        }
    }
}

/// A link that shows a suggestion is right (`SubmissionEvidenceInput`).
/// Photos aren't offered yet.
struct SuggestionEvidence: Hashable, Sendable {
    let url: String

    var graphQLInput: GraphQLValue {
        .object(["kind": .string("link"), "url": .string(url)])
    }
}

/// A suggestion to send with `submitContribution`.
struct SuggestionRequest: Hashable, Sendable {
    var kind: SuggestionKind
    /// The venue, event or recurring night it's about; none for a missing one.
    var targetID: String?
    var localeID: UUID?
    /// Only the fields it proposes, by their API names (`phone`, `start_at`).
    var proposed: [String: GraphQLValue] = [:]
    var body: String?
    var evidence: [SuggestionEvidence] = []
    /// For a missing venue or event the member says isn't the listing it
    /// matched.
    var notListed = false

    /// `submitContribution`'s variables. `notListed` is only sent when it's
    /// set, so the request still works against an API without it.
    var variables: [String: GraphQLValue] {
        var input: [String: GraphQLValue] = [
            "kind": .string(kind.rawValue),
            "proposed": .object(proposed),
            "evidence": .array(evidence.map(\.graphQLInput)),
        ]
        if let targetID { input["targetId"] = .string(targetID) }
        if let localeID { input["localeId"] = .string(localeID.uuidString.lowercased()) }
        if let body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            input["body"] = .string(body.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if notListed { input["notListed"] = .bool(true) }
        return ["input": .object(input)]
    }
}

/// What sending a suggestion did.
enum SuggestionOutcome: Hashable, Sendable {
    /// Filed. `merged` when someone else had suggested the same thing.
    case sent(id: String, merged: Bool)
    /// Nothing was filed: it's already listed as this venue or event.
    case alreadyListed(AlreadyListed)
}

/// The listing a missing venue or event matched.
struct AlreadyListed: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable { case venue, event }

    let kind: Kind
    let id: UUID
    let name: String

    var route: AppRoute { kind == .venue ? .venue(id) : .event(id) }
}

/// What the venue page needs that isn't in its main query (so the page still
/// loads from an API without contributions): whether it's reported closed,
/// and its details as a fix starts from.
struct VenueSuggestionState: Hashable, Sendable {
    var reportedClosed: Bool
    var name: String?
    var description: String?
    var website: String?
    var phone: String?
}
