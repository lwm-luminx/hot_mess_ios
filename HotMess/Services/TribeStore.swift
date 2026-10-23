//
//  TribeStore.swift
//  HotMess
//

import Foundation
import Observation

/// The tribes the user picked, the list they pick from, and whether the API
/// has tribes at all. Nobody sees anyone's list: a tribe shows only in venue
/// chat, and only to someone who picked it too (`SharedTribe`).
@MainActor
@Observable
final class TribeStore {
    /// `nil` until loaded, and on an API without the tribe catalog.
    private(set) var choices: TribeChoices?
    /// Whether the API serves tribes: `nil` until asked. Chat asks for
    /// shared tribes only when it does, since asking an API that doesn't
    /// have them would refuse the whole room.
    private(set) var isSupported: Bool?
    private var checkedAt: Date?

    /// How long an answer about support holds before chat asks again.
    static let supportCheckInterval: TimeInterval = 10 * 60

    private let api: HotMessAPI

    init(api: HotMessAPI) {
        self.api = api
    }

    /// Loads the list and the user's picks. `force` re-reads.
    func load(force: Bool = false) async {
        guard force || choices == nil else { return }

        do {
            choices = try await api.tribes()
            isSupported = true
        } catch {
            isSupported = false
        }
        checkedAt = .now
    }

    /// Whether to ask chat rooms for shared tribes: the last answer while
    /// it's fresh, else the API's.
    func supportsTribes() async -> Bool {
        if let isSupported, let checkedAt, Date.now.timeIntervalSince(checkedAt) < Self.supportCheckInterval {
            return isSupported
        }
        await load(force: true)
        return isSupported ?? false
    }

    /// Saves the picker's picks. Throws, keeping the earlier picks, when the
    /// API refuses them.
    func save(_ picked: Set<String>) async throws {
        let saved = try await api.setTribes(picked)
        choices?.picked = saved
    }

    func forget() {
        choices = nil
        isSupported = nil
        checkedAt = nil
    }
}
