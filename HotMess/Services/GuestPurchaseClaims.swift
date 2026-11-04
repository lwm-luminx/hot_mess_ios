import AudienceCore
import Foundation

/// Attaches the clip's guest covers and tips to whoever just signed in
/// (`claimGuestPurchases`). The clip calls it after Sign in with Apple; the
/// full app after its own sign-in, for tokens the clip left behind.
enum GuestPurchaseClaims {
    struct Outcome: Sendable {
        /// Claimed cover IDs: now the member's, read through the member API.
        var claimedAdmissionIDs: Set<String> = []
        var claimedTipIDs: Set<String> = []
        /// Covers left as guest passes: the member already has one that night.
        var keptTokens: Set<String> = []
    }

    /// Claims every waiting token. Errors leave the tokens for the next try.
    @discardableResult
    static func claim(client: AudienceSession, store: GuestPurchaseStore = .shared) async -> Outcome {
        store.update { $0.prune(today: GuestPurchaseList.today()) }
        let tokens = store.load().claimable(host: client.configuration.host)
        guard !tokens.isEmpty else { return Outcome() }
        do {
            let payload = try await client.graphQL(document, variables: ["tokens": .array(tokens.map { .string($0) })],
                                                   as: Response.self).claimGuestPurchases
            let notFound = Set(payload.unclaimed.filter { $0.reason != "ALREADY_HAS_COVER" }.map(\.claimToken))
            let kept = Set(payload.unclaimed.filter { $0.reason == "ALREADY_HAS_COVER" }.map(\.claimToken))
            let unclaimed = notFound.union(kept)
            let claimed = Set(tokens).subtracting(unclaimed)
            store.update { $0.apply(claimed: claimed, notFound: notFound, alreadyHasCover: kept) }
            return Outcome(claimedAdmissionIDs: Set(payload.admissions.map(\.id)),
                           claimedTipIDs: Set(payload.tips.map(\.id)), keptTokens: kept)
        } catch {
            return Outcome()
        }
    }

    private struct Response: Decodable, Sendable {
        struct Payload: Decodable, Sendable {
            struct Record: Decodable, Sendable { let id: String }
            struct Unclaimed: Decodable, Sendable { let claimToken: String; let reason: String }
            let admissions: [Record]
            let tips: [Record]
            let unclaimed: [Unclaimed]
        }
        let claimGuestPurchases: Payload
    }

    static let document = """
    mutation HotMessClaimGuestPurchases($tokens: [String!]!) {
      claimGuestPurchases(input: { claimTokens: $tokens }) {
        admissions { id }
        tips { id }
        unclaimed { claimToken reason }
      }
    }
    """
}
