//
//  ServerCards.swift
//  HotMess
//

import AudienceKit
import Foundation
import Observation

/// What a screen's cards are drawn from: the server's ranked layout
/// (`Audience.layout`) when it can be had, else the screen's built-in order.
/// The cards only order the screen and point at records by id; the content
/// still comes from the queries the screens already make.
@MainActor
@Observable
final class ScreenLayout {
    private(set) var layout: CardLayout
    private let client: LayoutClient
    private var loadedAt: ContinuousClock.Instant?

    init(audienceKit: AudienceKitClient, screen: LayoutScreen, kinds: [String], fallback: [String], appVersion: String) {
        client = LayoutClient(session: audienceKit, screen: screen, cardKinds: kinds, fallback: fallback,
                              appVersion: appVersion)
        layout = .fallback(fallback)
    }

    /// The server's order for where the device is, or the app's locale
    /// without a position. Asks again only once `refreshAfter` has passed,
    /// unless `force`.
    func load(coordinates: Coordinates?, localeID: UUID?, force: Bool = false) async {
        if !force, let loadedAt, ContinuousClock.now - loadedAt < .seconds(layout.refreshAfter) { return }
        let position = coordinates.map { AudienceKit.Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
        let fetched = await client.load(position: position, beaconMajor: coordinates?.beaconMajor,
                                        localeID: localeID?.uuidString.lowercased())
        guard !Task.isCancelled else { return }
        // A failed fetch keeps the server's last order rather than jumping back to the built-in one.
        if fetched.isFallback, !layout.isFallback { return }
        layout = fetched
        loadedAt = fetched.isFallback ? nil : .now
    }
}

/// The records a card points at, in the server's order, picked from what the
/// screen loaded. A built-in card (or one whose ids are all unknown here) gets
/// the screen's own list.
func ordered<Item: Identifiable>(_ items: [Item], by ids: [String], isFallback: Bool) -> [Item] where Item.ID == UUID {
    guard !isFallback, !ids.isEmpty else { return items }
    let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return ids.compactMap { UUID(uuidString: $0).flatMap { byID[$0] } }
}

/// The promoted-card categories the viewer turned off, kept on this device
/// (and their other Apple devices through iCloud) and never sent anywhere,
/// with the audience's published categories to name them.
@MainActor
@Observable
final class CardSettings {
    private(set) var hidden: Set<String>
    /// Nil until they load; the filter honours every hidden category until then.
    private(set) var categories: [CardCategory]?
    /// Says which promoted cards were seen, for the fair rotation.
    let views: PromoViewRecorder

    private let preferences: CardPreferences
    private let audienceKit: AudienceKitClient

    init(audienceKit: AudienceKitClient) {
        self.audienceKit = audienceKit
        preferences = CardPreferences()
        hidden = preferences.hidden
        views = PromoViewRecorder(session: audienceKit)
        preferences.onChange = { [weak self] hidden in
            Task { @MainActor [weak self] in self?.hidden = hidden }
        }
    }

    var filter: CardFilter { CardFilter(hidden: hidden, categories: categories) }

    func category(_ key: String) -> CardCategory? {
        categories?.first { $0.key == key }
    }

    func loadCategories() async {
        if let loaded = try? await audienceKit.cardCategories() { categories = loaded }
    }

    func setHidden(_ key: String, _ hide: Bool) {
        preferences.setHidden(key, hide)
        hidden = preferences.hidden
    }
}
