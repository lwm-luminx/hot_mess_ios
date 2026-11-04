import Foundation
#if canImport(Security)
import Security
#endif

/// A cover or tip the App Clip paid for before anyone signed in, and the
/// claim token that attaches it to an account later (`claimGuestPurchases`,
/// audience_kit_api doc/APP_CLIP_CHECKOUT.md). The token is the only key to
/// the purchase, so it lives in the keychain like a session.
struct GuestPurchase: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case cover, tip
    }

    let kind: Kind
    /// The admission's or tip's ID.
    let id: String
    let claimToken: String
    /// The audience host it was bought on (`host` in the clip's requests). A
    /// token is only claimed through that audience, so a build pointed at
    /// another API doesn't throw it away as not found.
    var host: String? = nil
    /// Cover only: where and for which night (`yyyy-MM-dd`), so the clip can
    /// show the pass again from the venue's link.
    var venueID: String? = nil
    var night: String? = nil
    var createdAt: Date = .now
    /// The member already held a cover that night (`ALREADY_HAS_COVER`): the
    /// guest pass stays a guest pass for the night and isn't claimed again.
    var keptAsGuest = false
}

/// The clip's guest purchases, oldest first. Pure bookkeeping, so
/// `Scripts/test-app-clip.sh` can check it.
struct GuestPurchaseList: Codable, Equatable, Sendable {
    /// Claim at most this many per `claimGuestPurchases` call (the API's limit).
    static let claimLimit = 20
    /// Tokens nobody claims are dropped after this long. A cover is for one
    /// night; a tip that was never claimed stays the performer's either way.
    static let lifetime: TimeInterval = 14 * 24 * 60 * 60

    var purchases: [GuestPurchase] = []

    mutating func add(_ purchase: GuestPurchase) {
        purchases.removeAll { $0.claimToken == purchase.claimToken }
        purchases.append(purchase)
    }

    mutating func remove(token: String) {
        purchases.removeAll { $0.claimToken == token }
    }

    /// Tokens to send to `claimGuestPurchases` on `host`, oldest first.
    func claimable(host: String?) -> [String] {
        let matching = purchases.filter { !$0.keptAsGuest && ($0.host == nil || $0.host == host) }
        return Array(matching.map(\.claimToken).prefix(Self.claimLimit))
    }

    /// What claiming answered: claimed and unknown tokens go; a cover the
    /// member already has one of that night stays, as a guest pass.
    mutating func apply(claimed: Set<String>, notFound: Set<String>, alreadyHasCover: Set<String>) {
        purchases.removeAll { claimed.contains($0.claimToken) || notFound.contains($0.claimToken) }
        for index in purchases.indices where alreadyHasCover.contains(purchases[index].claimToken) {
            purchases[index].keptAsGuest = true
        }
    }

    /// Drops purchases older than ``lifetime``, and guest passes kept for a
    /// night that has passed.
    mutating func prune(now: Date = .now, today: String) {
        purchases.removeAll { purchase in
            if now.timeIntervalSince(purchase.createdAt) > Self.lifetime { return true }
            if purchase.keptAsGuest, let night = purchase.night, night < today { return true }
            return false
        }
    }

    /// The newest cover bought here for `venueID` on `night`.
    func cover(venueID: String, night: String) -> GuestPurchase? {
        purchases.last { $0.kind == .cover && $0.venueID?.lowercased() == venueID.lowercased() && $0.night == night }
    }

    func purchase(id: String) -> GuestPurchase? {
        purchases.last { $0.id == id }
    }

    /// Yesterday's night or earlier is over; `yyyy-MM-dd` compares as text.
    /// A night runs 6am to 6am, so before 6am it's still last night.
    static func today(now: Date = .now, calendar: Calendar = .current) -> String {
        let shifted = now.addingTimeInterval(-6 * 60 * 60)
        let parts = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

#if canImport(Security)
/// Keeps the ``GuestPurchaseList`` in the clip's keychain service, beside the
/// clip's session (`HotMessAuthentication.clipStore`). iOS gives the full app
/// the clip's keychain items when it's installed, so the app reads the same
/// item and claims what's left after its own sign-in.
struct GuestPurchaseStore: Sendable {
    static let shared = GuestPurchaseStore()

    let service: String
    let account: String

    init(service: String = "social.hotmess.account.clip", account: String = "guest-purchases") {
        self.service = service
        self.account = account
    }

    func load() -> GuestPurchaseList {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let list = try? JSONDecoder().decode(GuestPurchaseList.self, from: data)
        else { return GuestPurchaseList() }
        return list
    }

    func save(_ list: GuestPurchaseList) {
        guard !list.purchases.isEmpty else {
            SecItemDelete(baseQuery as CFDictionary)
            return
        }
        guard let data = try? JSONEncoder().encode(list) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(baseQuery.merging(attributes) { current, _ in current } as CFDictionary, nil)
        }
    }

    /// Loads, changes and saves the list.
    @discardableResult
    func update<T>(_ change: (inout GuestPurchaseList) -> T) -> T {
        var list = load()
        let result = change(&list)
        save(list)
        return result
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
#endif
