//
//  ServerCards.swift
//  HotMess
//

import AudienceKit
import AudienceKitUI
import Foundation
import Observation

/// What a screen's cards are drawn from: the server's ranked layout
/// (`Audience.layout`) when it can be had, else the screen's built-in order.
/// The cards only order the screen and point at records by id; the content
/// still comes from the queries the screens already make.
@MainActor
@Observable
final class ScreenLayout {
    typealias Fetch = @Sendable (_ position: AudienceKit.Coordinate?, _ beaconMajor: Int?, _ localeID: String?) async
        -> CardLayout

    private(set) var layout: CardLayout
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let now: () -> ContinuousClock.Instant
    @ObservationIgnored private(set) var policy: LayoutRefreshPolicy
    /// The ask on the wire, which every other caller waits for instead of sending its own.
    @ObservationIgnored private var inFlight: Task<CardLayout, Never>?

    convenience init(audienceKit: AudienceKitClient, screen: LayoutScreen, kinds: [String], fallback: [String],
                     appVersion: String) {
        let client = LayoutClient(session: audienceKit, screen: screen, cardKinds: kinds, fallback: fallback,
                                  appVersion: appVersion)
        self.init(fallback: fallback, fetch: { position, beaconMajor, localeID in
            await client.load(position: position, beaconMajor: beaconMajor, localeID: localeID)
        })
    }

    init(fallback: [String], policy: LayoutRefreshPolicy = LayoutRefreshPolicy(),
         now: @escaping () -> ContinuousClock.Instant = { .now }, fetch: @escaping Fetch) {
        self.fetch = fetch
        self.now = now
        self.policy = policy
        layout = .fallback(fallback)
    }

    /// The server's order for where the device is, or the app's locale
    /// without a position. Asks only when ``LayoutRefreshPolicy`` says it's
    /// due (`force` is for a person pulling to refresh), never twice at once,
    /// and backs off after a failure so a slow server isn't asked harder.
    func load(coordinates: Coordinates?, localeID: UUID?, force: Bool = false) async {
        if let inFlight {
            _ = await inFlight.value
            return
        }
        let request = LayoutRefreshPolicy.Request(coordinates: coordinates, localeID: localeID)
        guard policy.isDue(request, at: now(), force: force) else { return }
        policy.asked(request, at: now())

        let position = coordinates.map { AudienceKit.Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
        let fetch = fetch, beaconMajor = coordinates?.beaconMajor, locale = localeID?.uuidString.lowercased()
        // Not tied to the caller: a screen's task cancelled mid-ask still gets
        // its answer recorded, rather than leaving the layout due at once.
        let task = Task { await fetch(position, beaconMajor, locale) }
        inFlight = task
        let fetched = await task.value
        inFlight = nil

        if fetched.isFallback {
            // A failed fetch keeps the server's last order rather than jumping back to the built-in one.
            policy.failed(at: now())
        } else {
            policy.succeeded(refreshAfter: fetched.refreshAfter, at: now())
            layout = fetched
        }
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

    /// AudienceKit's cards about getting Velvet or Backstage are skipped on a
    /// phone that has the app (checked here; the server never learns).
    var filter: CardFilter {
        CardFilter(hidden: hidden, categories: categories,
                   installedStaffApps: Set(StaffApp.allCases.filter(\.isInstalled)))
    }

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
