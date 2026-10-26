//
//  SafetyStore.swift
//  HotMess
//

import Foundation
import Observation

/// The user's blocks and whether they've agreed to the terms of use, which
/// chat needs before anyone can read or post. Also
/// whether the account has Facebook, and whether App Review lets it pretend
/// to be at a venue.
///
/// Blocking hides the person at once here; the API also stops sending their
/// messages and presence to the room within a minute.
@MainActor
@Observable
final class SafetyStore {
    private(set) var blockedUsers: [BlockedUser] = []
    private(set) var termsAcceptedAt: Date?
    /// Whether the API has said yet; until then chat waits rather than
    /// asking someone who already agreed.
    private(set) var isLoaded = false
    /// Assumed until the API says otherwise, so nobody who signed in with
    /// Facebook is asked to connect it.
    private(set) var hasFacebook = true
    private(set) var canPretendLocation = false

    private let api: HotMessAPI

    init(api: HotMessAPI) {
        self.api = api
    }

    var blockedIDs: Set<UUID> { Set(blockedUsers.map(\.id)) }

    var hasAcceptedTerms: Bool { termsAcceptedAt != nil }

    func isBlocked(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return blockedUsers.contains { $0.id == id }
    }

    /// Loads once per sign-in; `force` re-reads.
    func load(force: Bool = false) async {
        guard force || !isLoaded else { return }

        do {
            let state = try await api.safety()
            blockedUsers = state.blockedUsers
            termsAcceptedAt = state.termsAcceptedAt
            hasFacebook = state.hasFacebook
            canPretendLocation = state.canPretendLocation
            isLoaded = true
        } catch {
            // Chat asks again on the next visit.
        }
    }

    func acceptTerms() async throws {
        termsAcceptedAt = try await api.acceptTerms() ?? Date()
        isLoaded = true
    }

    /// The API refused something because the terms aren't agreed (an older
    /// answer said they were, or they were reset): ask again.
    func termsRefused() {
        termsAcceptedAt = nil
        isLoaded = true
    }

    /// Blocks someone, hiding them straight away and putting them back if the
    /// API refuses.
    func block(_ user: BlockedUser) async throws {
        let before = blockedUsers
        if !isBlocked(user.id) { blockedUsers.append(user) }
        do {
            blockedUsers = try await api.blockUser(user.id)
        } catch {
            blockedUsers = before
            throw error
        }
    }

    func unblock(_ id: UUID) async throws {
        blockedUsers = try await api.unblockUser(id)
    }

    /// Reports a message to the room's admins. Blocking with it hides the
    /// sender at once.
    func report(messageID: UUID, sender: BlockedUser?, reason: ChatReportReason, block: Bool) async throws {
        try await api.reportChatMessage(messageID, reason: reason.rawValue, block: block)
        if block, let sender, !isBlocked(sender.id) {
            blockedUsers.append(sender)
        }
    }

    /// Reports a person, venue, Ping, photo or message (`reportContent`).
    /// Blocking with it hides whoever is behind it at once.
    func report(_ subject: ReportSubject, reason: ChatReportReason, block: Bool) async throws {
        try await api.reportContent(subject.target, id: subject.targetID, reason: reason.rawValue, block: block)
        if block, let sender = subject.sender, !isBlocked(sender.id) {
            blockedUsers.append(sender)
        }
    }

    /// Forgets everything, for sign-out and account deletion.
    func forget() {
        blockedUsers = []
        termsAcceptedAt = nil
        hasFacebook = true
        canPretendLocation = false
        isLoaded = false
    }
}
