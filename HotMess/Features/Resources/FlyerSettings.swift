//
//  FlyerSettings.swift
//  HotMess
//

import AudienceKit
import Foundation
import Observation

/// Digital flyers on this phone: which flyers and kinds of flyer were hidden,
/// the words around them, and the city's resource directory.
///
/// Hidden flyers and kinds live in `UserDefaults` on this phone only, never
/// iCloud and never sent anywhere, because which kinds of help someone hid is
/// nobody else's business. The directory is fetched whole for the city,
/// without the session token, as soon as the city is known. Choosing "I
/// need…" then filters it here, so the choice makes no request at all.
@MainActor
@Observable
final class FlyerSettings {
    private(set) var dismissed: Set<String>
    private(set) var hiddenCategories: Set<String>
    /// Nil until it loads.
    private(set) var copy: FlyerCopy?
    /// The city's directory, once fetched.
    private(set) var directory: CommunityDirectory?
    private(set) var directoryFailed = false

    private let dismissals: FlyerDismissals
    private let picker: FlyerLinePicker
    private let audienceKit: AudienceKitClient
    private var directoryTask: Task<Void, Never>?

    init(audienceKit: AudienceKitClient, defaults: UserDefaults = .standard) {
        self.audienceKit = audienceKit
        dismissals = FlyerDismissals(defaults: defaults)
        picker = FlyerLinePicker(defaults: defaults)
        dismissed = Set(dismissals.dismissedFlyers)
        hiddenCategories = dismissals.hiddenCategories
    }

    /// The card's flyers this phone hasn't hidden.
    func visible(_ content: FlyersCardContent) -> [DigitalFlyer] {
        content.flyers.filter { !dismissed.contains($0.id) && !hiddenCategories.contains($0.category) }
    }

    /// The line a flyer shows, picked once when it appears: never the one shown last.
    func line(for flyer: DigitalFlyer) -> String? { picker.line(for: flyer) }

    func categoryLabel(_ key: String) -> String {
        copy?.categories.first { $0.key == key }?.label ?? key.replacingOccurrences(of: "-", with: " ").capitalized
    }

    func dismiss(_ flyer: DigitalFlyer) {
        dismissals.dismiss(flyer)
        dismissed = Set(dismissals.dismissedFlyers)
    }

    func setHidden(category: String, _ hide: Bool) {
        dismissals.setHidden(category: category, hide)
        hiddenCategories = dismissals.hiddenCategories
    }

    /// Shows every flyer and kind again.
    func reset() {
        dismissals.reset()
        dismissed = []
        hiddenCategories = []
    }

    func loadCopy() async {
        guard copy == nil else { return }
        if let loaded = try? await audienceKit.flyerCopy() { copy = loaded }
    }

    /// Fetches the city's directory unless it's already here (or on its way).
    func prefetchDirectory(localeID: UUID?) {
        guard let localeID else { return }
        let id = localeID.uuidString.lowercased()
        if directory?.locale.id.lowercased() == id { return }
        directoryTask?.cancel()
        directoryTask = Task { [audienceKit] in
            do {
                let loaded = try await audienceKit.communityDirectory(localeID: id)
                guard !Task.isCancelled else { return }
                directory = loaded
                directoryFailed = false
            } catch {
                if !Task.isCancelled { directoryFailed = true }
            }
        }
    }

    /// Waits for a fetch under way.
    func awaitDirectory() async { await directoryTask?.value }
}
