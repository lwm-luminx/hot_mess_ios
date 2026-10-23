//
//  ListingsStore.swift
//  HotMess
//

import Foundation
import Observation

/// The venues and talent the signed-in user manages, so their pages offer
/// "New Post" and their posts' menus offer editing. Most people manage none;
/// the API still checks every change.
@MainActor
@Observable
final class ListingsStore {
    private(set) var listings = ManagedListings.none
    private(set) var isLoaded = false

    private let api: HotMessAPI

    init(api: HotMessAPI) {
        self.api = api
    }

    /// Loads once per sign-in; `force` re-reads.
    func load(force: Bool = false) async {
        guard force || !isLoaded else { return }
        listings = await api.managedListings()
        isLoaded = true
    }

    func forget() {
        listings = .none
        isLoaded = false
    }

    func canManage(_ post: Post) -> Bool { listings.canManage(post) }

    func canHideFromEvent(_ post: Post) -> Bool { listings.canHideFromEvent(post) }
}
