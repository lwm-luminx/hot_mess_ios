//
//  ManagedListings.swift
//  HotMess
//

import Foundation

/// The venues and talent the signed-in user manages here (`me { listings }`),
/// empty for everyone else. Hot Mess doesn't write or manage posts: Me sends
/// venue managers to Velvet and talent to Backstage, where they do.
struct ManagedListings: Hashable, Sendable {
    struct Listing: Hashable, Sendable {
        let id: UUID
        let name: String
    }

    var venues: [Listing] = []
    var people: [Listing] = []

    var isEmpty: Bool { venues.isEmpty && people.isEmpty }

    static let none = ManagedListings()
}
