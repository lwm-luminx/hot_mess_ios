//
//  HotMessAPI+SafetyAlerts.swift
//  HotMess
//

import AudienceKit
import Foundation

/// Safety alerts: "I feel unsafe" to the staff on shift at the venue the user
/// is at, its private thread, and "Need support?" (api doc/SAFETY_ALERTS.md).
/// The venue's own query doesn't ask for any of it, so an API without these
/// fields still shows the venue.
extension HotMessAPI {
    /// Whether the user can send an alert at the venue, and whether anyone
    /// on shift there hears them.
    func venueSafety(_ venueID: UUID) async throws -> VenueSafety? {
        let venue = try await query(
            SafetyAlertDocuments.venueSafety,
            variables: ["id": .string(venueID.uuidString.lowercased())],
            as: VenueSafetyResponse.self
        ).venues?.venue
        return venue.map { VenueSafety(canSend: $0.canSendSafetyAlert, staffOnShift: $0.safetyStaffOnShift) }
    }

    /// Tells the staff on shift. While the user's alert there is open, the
    /// API adds what they picked to it instead.
    func sendSafetyAlert(venueID: UUID, _ draft: SafetyAlertDraft) async throws -> SafetyAlert {
        var variables = draft.variables
        variables["venueId"] = .string(venueID.uuidString.lowercased())
        return try await alert(from: query(SafetyAlertDocuments.send, variables: variables, as: SendResponse.self)
            .sendSafetyAlert.safetyAlert)
    }

    /// "Add more": where they are and what's going on, after sending.
    func updateSafetyAlert(_ id: String, _ draft: SafetyAlertDraft) async throws -> SafetyAlert {
        var variables = draft.variables
        variables["id"] = .string(id)
        return try await alert(from: query(SafetyAlertDocuments.update, variables: variables, as: UpdateResponse.self)
            .updateSafetyAlert.safetyAlert)
    }

    /// "Tell staff again": rings the staff on shift and the venue's managers.
    func remindSafetyAlert(_ id: String) async throws -> SafetyAlert {
        try await alert(from: query(SafetyAlertDocuments.remind, variables: ["id": .string(id)], as: RemindResponse.self)
            .remindSafetyAlert.safetyAlert)
    }

    /// "I'm OK now, cancel the alert".
    func cancelSafetyAlert(_ id: String) async throws -> SafetyAlert {
        try await alert(from: query(SafetyAlertDocuments.cancel, variables: ["id": .string(id)], as: CancelResponse.self)
            .cancelSafetyAlert.safetyAlert)
    }

    /// A message in the alert's private thread, never shown in venue chat.
    func sendSafetyAlertMessage(_ id: String, body: String) async throws -> SafetyAlert {
        try await alert(from: query(
            SafetyAlertDocuments.message,
            variables: ["id": .string(id), "body": .string(body)],
            as: MessageResponse.self
        ).sendSafetyAlertMessage.safetyAlert)
    }

    /// One of the user's alerts, as it stands now.
    func safetyAlert(_ id: String) async throws -> SafetyAlert? {
        try await query(SafetyAlertDocuments.one, variables: ["id": .string(id)], as: OneResponse.self).me?.safetyAlert
    }

    /// The user's alerts that are still open, and those closed in the last day.
    func safetyAlerts() async throws -> [SafetyAlert] {
        try await query(SafetyAlertDocuments.mine, variables: [:], as: MineResponse.self).me?.safetyAlerts ?? []
    }

    /// "Need support?" for a region (ISO 3166-2 like US-UT, or a country);
    /// the API falls back to the country, then its default.
    func supportResources(region: String?) async throws -> SupportResources {
        try await query(
            SafetyAlertDocuments.support,
            variables: ["region": region.map(GraphQLValue.string) ?? .null],
            as: SupportResponse.self
        ).supportResources
    }

    private func alert(from alert: SafetyAlert?) throws -> SafetyAlert {
        guard let alert else { throw APIError.decoding("safetyAlert") }
        return alert
    }
}

extension SafetyAlertDraft {
    fileprivate var variables: [String: GraphQLValue] {
        [
            "place": place.map { .string($0.rawValue) } ?? .null,
            "concerns": .array(SafetyConcern.allCases.filter(concerns.contains).map { .string($0.rawValue) }),
            "description": trimmedDescription.map(GraphQLValue.string) ?? .null,
        ]
    }
}

enum SafetyAlertDocuments {
    private static let alert = """
    id state place concerns description summary seen acknowledgedByName acknowledgedAt escalatedAt closedAt \
    supportSharedAt supportNote createdAt venue { id name } messages { id body fromStaff senderName createdAt }
    """

    static let venueSafety = """
    query VenueSafety($id: ID!) {
      venues { venue(id: $id) { id canSendSafetyAlert safetyStaffOnShift } }
    }
    """

    static let send = """
    mutation SendSafetyAlert($venueId: ID!, $place: SafetyAlertPlace, $concerns: [SafetyAlertConcern!], $description: String) {
      sendSafetyAlert(input: { venueId: $venueId, place: $place, concerns: $concerns, description: $description }) {
        safetyAlert { \(alert) }
      }
    }
    """

    static let update = """
    mutation UpdateSafetyAlert($id: ID!, $place: SafetyAlertPlace, $concerns: [SafetyAlertConcern!], $description: String) {
      updateSafetyAlert(input: { id: $id, place: $place, concerns: $concerns, description: $description }) {
        safetyAlert { \(alert) }
      }
    }
    """

    static let remind = """
    mutation RemindSafetyAlert($id: ID!) {
      remindSafetyAlert(input: { id: $id }) { safetyAlert { \(alert) } }
    }
    """

    static let cancel = """
    mutation CancelSafetyAlert($id: ID!) {
      cancelSafetyAlert(input: { id: $id }) { safetyAlert { \(alert) } }
    }
    """

    static let message = """
    mutation SendSafetyAlertMessage($id: ID!, $body: String!) {
      sendSafetyAlertMessage(input: { id: $id, body: $body }) { safetyAlert { \(alert) } }
    }
    """

    static let one = """
    query SafetyAlert($id: ID!) {
      me { safetyAlert(id: $id) { \(alert) } }
    }
    """

    static let mine = """
    query MySafetyAlerts {
      me { safetyAlerts { \(alert) } }
    }
    """

    static let support = """
    query SupportResources($region: String) {
      supportResources(region: $region) {
        region name emergency checkedAt
        lines { id name description phone textNumber textBody url }
        rides { id name url pickupUrl }
      }
    }
    """
}

private struct VenueSafetyResponse: Decodable, Sendable {
    struct Venue: Decodable, Sendable {
        let canSendSafetyAlert: Bool
        let safetyStaffOnShift: Bool
    }

    struct Venues: Decodable, Sendable { let venue: Venue? }

    let venues: Venues?
}

private struct AlertPayload: Decodable, Sendable { let safetyAlert: SafetyAlert? }
private struct SendResponse: Decodable, Sendable { let sendSafetyAlert: AlertPayload }
private struct UpdateResponse: Decodable, Sendable { let updateSafetyAlert: AlertPayload }
private struct RemindResponse: Decodable, Sendable { let remindSafetyAlert: AlertPayload }
private struct CancelResponse: Decodable, Sendable { let cancelSafetyAlert: AlertPayload }
private struct MessageResponse: Decodable, Sendable { let sendSafetyAlertMessage: AlertPayload }

private struct OneResponse: Decodable, Sendable {
    struct Me: Decodable, Sendable { let safetyAlert: SafetyAlert? }
    let me: Me?
}

private struct MineResponse: Decodable, Sendable {
    struct Me: Decodable, Sendable { let safetyAlerts: [SafetyAlert] }
    let me: Me?
}

private struct SupportResponse: Decodable, Sendable { let supportResources: SupportResources }
