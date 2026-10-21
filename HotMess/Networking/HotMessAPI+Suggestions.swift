//
//  HotMessAPI+Suggestions.swift
//  HotMess
//

import AudienceKit
import Foundation

/// Suggestions: members telling us about a missing venue or event, a detail
/// that's wrong, or a venue that has closed. Nothing changes a listing until
/// a person approves it, and the venue never learns who sent it.
extension HotMessAPI {
    /// Sends a suggestion. A missing venue or event that's already listed
    /// files nothing and comes back as `.alreadyListed`, unless the member
    /// said it's a different place (`notListed`).
    func suggest(_ request: SuggestionRequest) async throws -> SuggestionOutcome {
        let payload = try await query(
            SuggestionDocuments.submit,
            variables: request.variables,
            as: SubmitContributionResponse.self
        ).submitContribution

        if let venue = payload.existingVenue, let id = UUID(uuidString: venue.id) {
            return .alreadyListed(AlreadyListed(kind: .venue, id: id, name: venue.name ?? ""))
        }
        if let event = payload.existingEvent, let id = UUID(uuidString: event.id) {
            return .alreadyListed(AlreadyListed(kind: .event, id: id, name: event.name ?? ""))
        }
        guard let submission = payload.submission else { throw APIError.decoding("submitContribution") }
        return .sent(id: submission.id, merged: payload.merged)
    }

    /// The member's own suggestions, newest first.
    func mySuggestions() async throws -> [SuggestionSummary] {
        try await query(SuggestionDocuments.mine, variables: [:], as: MySuggestionsResponse.self).me?.submissions ?? []
    }

    /// Whether the venue is reported closed, and its details as a fix starts
    /// from. Its own request, so the venue page doesn't depend on it.
    func venueSuggestionState(_ venueID: UUID) async throws -> VenueSuggestionState? {
        let venue = try await query(
            SuggestionDocuments.venueState,
            variables: ["id": .string(venueID.uuidString.lowercased())],
            as: VenueSuggestionStateResponse.self
        ).venues?.venue
        return venue.map {
            VenueSuggestionState(
                reportedClosed: $0.reportedClosed,
                name: $0.name,
                description: $0.description,
                website: $0.profile?.website,
                phone: $0.profile?.phone
            )
        }
    }

    /// "It's still open", on a venue reported closed. Returns whether it's
    /// still reported closed afterwards.
    func reportVenueOpen(_ venueID: UUID, note: String?) async throws -> Bool {
        var input: [String: GraphQLValue] = ["venueId": .string(venueID.uuidString.lowercased())]
        if let note, !note.isEmpty { input["body"] = .string(note) }
        return try await query(
            SuggestionDocuments.reportVenueOpen,
            variables: ["input": .object(input)],
            as: ReportVenueOpenResponse.self
        ).reportVenueOpen.venue.reportedClosed
    }
}

enum SuggestionDocuments {
    static let submit = """
    mutation SubmitContribution($input: ContributionSubmitInput!) {
      submitContribution(input: $input) {
        merged submission { id } existingVenue { id name } existingEvent { id name }
      }
    }
    """

    static let mine = """
    query MySuggestions {
      me { submissions(limit: 50) {
        id kind status reporterCount proposed createdAt
        venue { id name } event { id name } decisions { action reason }
      } }
    }
    """

    static let venueState = """
    query VenueSuggestionState($id: ID!) {
      venues { venue(id: $id) { id name description reportedClosed profile { website phone } } }
    }
    """

    static let reportVenueOpen = """
    mutation ReportVenueOpen($input: VenueOpenReportInput!) {
      reportVenueOpen(input: $input) { venue { id reportedClosed } }
    }
    """
}

struct SubmitContributionResponse: Decodable, Sendable {
    struct Listing: Decodable, Sendable {
        let id: String
        let name: String?
    }

    struct Submission: Decodable, Sendable { let id: String }

    struct Payload: Decodable, Sendable {
        let merged: Bool
        let submission: Submission?
        let existingVenue: Listing?
        let existingEvent: Listing?
    }

    let submitContribution: Payload
}

struct MySuggestionsResponse: Decodable, Sendable {
    struct Me: Decodable, Sendable { let submissions: [SuggestionSummary] }

    let me: Me?
}

struct VenueSuggestionStateResponse: Decodable, Sendable {
    struct Profile: Decodable, Sendable {
        let website: String?
        let phone: String?
    }

    struct Venue: Decodable, Sendable {
        let id: String
        let name: String?
        let description: String?
        let reportedClosed: Bool
        let profile: Profile?
    }

    struct Venues: Decodable, Sendable { let venue: Venue? }

    let venues: Venues?
}

struct ReportVenueOpenResponse: Decodable, Sendable {
    struct Venue: Decodable, Sendable { let reportedClosed: Bool }
    struct Payload: Decodable, Sendable { let venue: Venue }

    let reportVenueOpen: Payload
}
