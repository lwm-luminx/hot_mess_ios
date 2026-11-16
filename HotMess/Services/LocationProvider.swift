//
//  LocationProvider.swift
//  HotMess
//

import CoreLocation
import Foundation
import Observation
import os
import UIKit

/// Tracks where the device is and which locale (city) that maps to.
///
/// Replaces `LocationService`, which mixed Core Location, HTTP calls, two
/// notification names and a `UIAlertController` into one singleton — and which
/// assigned the beacon *minor* value to `beaconMajor` twice, so ranging never
/// reported a usable pair.
@MainActor
@Observable
final class LocationProvider {
    private(set) var coordinates: Coordinates?
    /// How accurate the device fix behind `coordinates` is, in metres; `nil`
    /// while pretending to be at a venue.
    private var accuracy: CLLocationAccuracy?
    /// Told each time the API resolves the locale the device is in, changed
    /// or not: the cache refresher remembers it (on the phone only).
    @ObservationIgnored var onLocaleResolved: (@MainActor (AppLocale) -> Void)?
    private(set) var locale: AppLocale?
    private(set) var authorizationStatus: CLAuthorizationStatus
    /// Test builds and App Review only: the venue the app is pretending to be
    /// at. While it's set, the venue's position is reported instead of the
    /// device's.
    var simulatedVenueName: String? { tracker.simulatedVenueName }

    private var tracker: PositionTracker

    private let api: HotMessAPI
    private let configuration: AppConfiguration
    private let manager = CLLocationManager()
    private let delegate = Delegate()
    private var beaconConstraint: CLBeaconIdentityConstraint?
    private var beaconRegion: CLBeaconRegion?
    /// Significant changes, beacon regions and geofences: what keeps running
    /// in the background once the user allows Always.
    private var isMonitoring = false
    /// The 5-minute refresh and beacon ranging: only while the app is open.
    private var isInForeground = false
    /// Set when When In Use is asked for in this launch, so the upgrade to
    /// Always waits for a later launch instead of stacking a second prompt.
    private var askedWhenInUseThisLaunch = false
    /// True between `start()` or `startInBackground()` and `forget()`: only a
    /// signed-in app tracks, even when the authorization changes underneath it.
    private var isEnabled = false

    /// Callers waiting on `refreshPosition()`, resumed by the next fix, a
    /// failure, or their timeout.
    private var pendingFixes: [UUID: CheckedContinuation<Void, Never>] = [:]
    /// Re-reads the position every `refreshInterval` while the app is open.
    private var refreshTask: Task<Void, Never>?

    /// Watches the nearest venues' envelopes. See `GeofencePlan`.
    private var monitor: CLMonitor?
    private var monitorTask: Task<Void, Never>?
    private var geofencePlan: GeofencePlan?
    private var venueFences: [VenueFence] = []
    private var venueFencesFetchedAt: Date?
    private var isPlanningGeofences = false

    /// Fixes, beacons, geofences, chat and the Now screen all report the
    /// position; they share one request per place. See `now(sentAfter:)`.
    private var reportThrottle = ReportThrottle(
        minimumDistance: LocationProvider.reportDistance,
        maximumAge: LocationProvider.reportMaxAge
    )
    private var report: Report?
    /// The locale is looked up once per place, however often it's asked.
    private var localeThrottle = ReportThrottle(minimumDistance: LocationProvider.localeLookupDistance)
    private var localeLookup: Task<Void, Never>?

    /// The latest position report, in flight or answered.
    private struct Report {
        let sentAt: Date
        let task: Task<Now, any Error>
    }

    /// Remembered so the first launch after a cold start has a locale to work
    /// with before Core Location produces a fix.
    private static let storedLocaleIDKey = "localeId"
    private static let storedLocaleNameKey = "localeName"
    /// iOS shows the Always prompt once; this keeps the app from asking again.
    private static let askedForAlwaysKey = "askedForAlwaysLocation"

    init(api: HotMessAPI, configuration: AppConfiguration) {
        self.api = api
        self.configuration = configuration
        authorizationStatus = manager.authorizationStatus
        tracker = PositionTracker(simulationAllowed: configuration.isTestBuild)

        locale = Self.restoreLocale()

        if let beaconUUID = configuration.beaconUUID {
            beaconConstraint = CLBeaconIdentityConstraint(uuid: beaconUUID)
            beaconRegion = CLBeaconRegion(uuid: beaconUUID, identifier: Self.beaconIdentifier)
        }

        manager.delegate = delegate
        manager.pausesLocationUpdatesAutomatically = true
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        delegate.owner = self
    }

    static let beaconIdentifier = "social.hotmess.beacon"
    /// CLMonitor names must be alphanumeric: a dot throws "Monitor name is not
    /// valid" when the monitor is created, crashing the app at launch.
    static let monitorName = "HotMessVenues"
    static let recenterIdentifier = "recenter"
    static let venueIdentifierPrefix = "venue:"

    /// How often the position is re-read while the app is open. Presence on
    /// the API lasts two hours, so this keeps it current without keeping GPS on.
    static let refreshInterval: Duration = .seconds(5 * 60)
    /// How long `refreshPosition()` waits for Core Location before giving up.
    static let fixTimeout: Duration = .seconds(10)
    /// A fix this recent is used as is when the app comes back.
    static let freshFixAge: TimeInterval = 60
    /// Venue envelopes are downloaded again after this long.
    static let venueFencesMaxAge: TimeInterval = 6 * 60 * 60
    /// The position is reported again once it's moved this far…
    static let reportDistance: CLLocationDistance = 50
    /// …or the last report is this old.
    static let reportMaxAge: TimeInterval = 60
    /// Locales are cities: the locale is looked up again once the position
    /// has moved this far.
    static let localeLookupDistance: CLLocationDistance = 500

    /// Geofences and significant changes wake the app only with Always.
    var tracksInBackground: Bool {
        authorizationStatus == .authorizedAlways
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    /// True once the user has been asked and said no — the cue to offer a
    /// link into Settings instead of asking again.
    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    // MARK: - Control

    /// The app came to the foreground: track the device, refresh the
    /// position every `refreshInterval` and range beacons.
    func start() {
        isEnabled = true
        switch authorizationStatus {
        case .notDetermined:
            askedWhenInUseThisLaunch = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            askForAlwaysIfDue()
            beginMonitoring()
            beginForeground()
        case .authorizedAlways:
            beginMonitoring()
            beginForeground()
        default:
            break
        }
    }

    /// The app was launched or woken in the background, by a geofence or a
    /// significant change. Re-creating the monitor is what delivers the event.
    func startInBackground() {
        guard tracksInBackground else { return }
        isEnabled = true
        beginMonitoring()
    }

    /// The app went to the background. With Always, significant changes and
    /// venue geofences keep running so entering or leaving a venue is still
    /// reported; otherwise everything stops until the app comes back.
    func stop() {
        endForeground()
        guard !tracksInBackground else { return }
        endMonitoring()
    }

    /// Signing out: stop everything, background included, and drop the
    /// venue geofences so a signed-out app is never woken for them.
    func forget() {
        isEnabled = false
        endForeground()
        endMonitoring()

        // The monitor itself stays: only one may exist per name, and signing
        // in again picks it up. Without conditions it never wakes the app.
        geofencePlan = nil
        venueFences = []
        venueFencesFetchedAt = nil
        if let monitor {
            Task {
                for identifier in await monitor.identifiers {
                    await monitor.remove(identifier)
                }
            }
        }
    }

    private func endMonitoring() {
        guard isMonitoring else { return }

        manager.stopMonitoringSignificantLocationChanges()
        // Nobody is left waiting on a fix asked for before the app went away,
        // so coming back asks Core Location again rather than wait on it.
        resumePendingFixes()

        if let beaconRegion {
            manager.stopMonitoring(for: beaconRegion)
        }

        isMonitoring = false
    }

    /// Asks once to upgrade When In Use to Always, on a launch after the first
    /// prompt, so venue arrivals and departures count with the app closed.
    private func askForAlwaysIfDue() {
        let defaults = UserDefaults.standard
        guard !askedWhenInUseThisLaunch, !defaults.bool(forKey: Self.askedForAlwaysKey) else { return }

        defaults.set(true, forKey: Self.askedForAlwaysKey)
        manager.requestAlwaysAuthorization()
    }

    /// Asks Core Location for a fresh fix and returns once it's in and
    /// reported, Core Location gives up, or `fixTimeout` passes. Pull to
    /// refresh calls this, so a refresh never reloads around a stale position.
    func refreshPosition() async {
        guard isAuthorized else { return }

        let id = UUID()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.fixTimeout)
            self?.resumeFix(id)
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // One request answers everyone waiting: geofence events tend to
            // arrive several at once, and each asked for its own fix.
            let isAsking = !pendingFixes.isEmpty
            pendingFixes[id] = continuation
            if !isAsking { manager.requestLocation() }
        }
    }

    private func resumeFix(_ id: UUID) {
        pendingFixes.removeValue(forKey: id)?.resume()
    }

    private func resumePendingFixes() {
        let waiting = pendingFixes.values
        pendingFixes.removeAll()
        waiting.forEach { $0.resume() }
    }

    /// Asks the API which locale the current position belongs to, once per
    /// place: a lookup in flight is waited on rather than repeated, and the
    /// position must move `localeLookupDistance` before it's asked again.
    func refreshLocale() async {
        if let localeLookup { await localeLookup.value }
        guard let coordinates, localeThrottle.isDue(coordinates) else { return }

        localeThrottle.sent(coordinates)
        let lookup = Task { @MainActor [api, weak self] in
            do {
                let resolved = try await api.closestLocale(to: coordinates)
                guard let self, let resolved else { return }
                // Every visit counts, so a city the person stays in keeps
                // being refreshed.
                onLocaleResolved?(resolved)
                guard resolved.id != locale?.id else { return }

                locale = resolved
                LocationProvider.persist(resolved)
            } catch {
                // Ask again next time rather than wait to move.
                self?.localeThrottle.reset()
                Log.location.error("Locale lookup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        localeLookup = lookup
        await lookup.value
        if localeLookup == lookup { localeLookup = nil }
    }

    // MARK: - Testing

    /// Reports `coordinate` as the device's position until `stopSimulating()`,
    /// so a test build can be "at" a venue from anywhere. The API puts the
    /// user at whichever venue's envelope contains the point.
    /// Returns once the position is reported, so the caller can reload.
    /// `allowed` lets a release build do it too, for App Review.
    func simulate(at coordinate: CLLocationCoordinate2D, venueName: String, allowed: Bool = false) async {
        guard tracker.simulate(latitude: coordinate.latitude, longitude: coordinate.longitude,
                               venueName: venueName, allowed: allowed)
        else { return }

        coordinates = tracker.current
        accuracy = nil
        await refreshLocale()
        await reportPosition(force: true)
    }

    /// Goes back to the device's real position.
    func stopSimulating() async {
        guard tracker.stopSimulating() else { return }

        coordinates = tracker.current
        guard coordinates != nil else { return }

        await refreshLocale()
        await reportPosition(force: true)
    }

    // MARK: - Delegate plumbing

    private func beginMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        manager.startMonitoringSignificantLocationChanges()

        if let beaconRegion {
            manager.startMonitoring(for: beaconRegion)
        }

        startGeofencing()
    }

    private func beginForeground() {
        guard !isInForeground else { return }
        isInForeground = true

        if let beaconConstraint {
            manager.startRangingBeacons(satisfying: beaconConstraint)
        }

        // A recent cached fix shows something at once, but it may be a coarse
        // one (a cell tower, another app's), so a fresh fix is always asked for
        // too; opening the app shouldn't need a pull to refresh to find the venue.
        if let location = manager.location {
            update(with: location)
        }
        Task { await refreshPosition() }

        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled else { return }
                await self?.refreshPosition()
            }
        }
    }

    private func endForeground() {
        guard isInForeground else { return }
        isInForeground = false

        refreshTask?.cancel()
        refreshTask = nil
        if let beaconConstraint {
            manager.stopRangingBeacons(satisfying: beaconConstraint)
        }
    }

    fileprivate func authorizationChanged(to status: CLAuthorizationStatus) {
        authorizationStatus = status

        guard isAuthorized, isEnabled else { return }
        beginMonitoring()
        if UIApplication.shared.applicationState != .background {
            beginForeground()
        }
    }

    fileprivate func update(with location: CLLocation) {
        // Starting significant-change monitoring hands back the last fix the
        // system had, however old; reporting it would put the user wherever
        // they were then. A refresh waits on for the fix it asked for.
        guard location.horizontalAccuracy >= 0,
              Date.now.timeIntervalSince(location.timestamp) < Self.freshFixAge else { return }

        // Geofences follow the device, even while pretending to be elsewhere.
        Task { await withBackgroundTime("Plan venue geofences") { await planGeofences(around: location) } }

        guard tracker.deviceFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        else {
            resumePendingFixes()
            return
        }

        coordinates = tracker.current
        accuracy = location.horizontalAccuracy
        // A refresh waits for the locale too, so a pulled list reloads in the right city.
        Task {
            await withBackgroundTime("Report position") {
                await refreshLocale()
                await reportPosition()
            }
            resumePendingFixes()
        }
    }

    fileprivate func fixFailed() {
        resumePendingFixes()
    }

    fileprivate func update(beacons: [CLBeacon]) {
        guard let nearest = beacons.first else { return }

        // A beacon can be heard before the first significant-change fix.
        if tracker.current == nil, let location = manager.location {
            tracker.deviceFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        }
        guard tracker.beacon(major: nearest.major.intValue, minor: nearest.minor.intValue) else { return }

        coordinates = tracker.current
        Task { await reportPosition() }
    }

    /// Reports the current position, unless it was reported from about here
    /// in the last minute. Venue chat calls this so the API knows the user is
    /// still at the venue.
    func reportCurrentPosition() async {
        await reportPosition()
    }

    /// What's happening where the user is, from reporting the position, or
    /// `nil` with no position yet.
    ///
    /// Everything that reports the position comes through here and shares
    /// one request: a report sent from within `reportDistance` in the last
    /// `reportMaxAge`, in flight or answered, is used again rather than sent
    /// again or cancelled, unless it was sent before `sentAfter` (a pull to
    /// refresh, or Pings that changed since).
    func now(sentAfter: Date? = nil) async throws -> Now? {
        guard let coordinates else { return nil }

        if let report, !reportThrottle.isDue(coordinates, accuracy: accuracy),
           sentAfter.map({ report.sentAt >= $0 }) ?? true {
            return try await report.task.value
        }

        let sentAt = Date.now
        reportThrottle.sent(coordinates, accuracy: accuracy, at: sentAt)
        let task = Task { @MainActor [api, weak self] () throws -> Now in
            do {
                return try await api.now(near: coordinates)
            } catch {
                // The next caller tries again rather than sharing the failure.
                if let self, report?.sentAt == sentAt {
                    report = nil
                    reportThrottle.reset()
                }
                throw error
            }
        }
        report = Report(sentAt: sentAt, task: task)
        return try await task.value
    }

    /// Reports the position. `force` sends it even if about here was reported
    /// recently: pretending moves the user into a venue's envelope that may be
    /// only metres away.
    private func reportPosition(force: Bool = false) async {
        do {
            _ = try await now(sentAfter: force ? .now : nil)
        } catch {
            Log.location.error("Location report failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Geofences

    /// Starts watching venue envelopes. The monitor outlives the app's
    /// launches, so its regions from last time are still there; the first fix
    /// replaces them.
    private func startGeofencing() {
        guard monitorTask == nil else { return }

        monitorTask = Task { @MainActor [weak self] in
            let monitor = await CLMonitor(Self.monitorName)
            self?.monitor = monitor
            // Signed out while the monitor was being created: drop last
            // session's regions rather than wake for them.
            if self?.isEnabled != true {
                for identifier in await monitor.identifiers {
                    await monitor.remove(identifier)
                }
            }
            if let location = self?.manager.location {
                await self?.planGeofences(around: location)
            }

            do {
                for try await event in await monitor.events {
                    await self?.geofenceChanged(event.identifier, inside: event.state == .satisfied)
                }
            } catch {
                Log.location.error("Geofence monitoring stopped: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Entering or leaving a venue means presence changed: read the position
    /// and report it. Leaving the re-center circle means unwatched venues may
    /// be close now, so the regions are planned again from the new fix.
    private func geofenceChanged(_ identifier: String, inside: Bool) async {
        if identifier == Self.recenterIdentifier {
            guard !inside else { return }
            geofencePlan = nil
        } else if !identifier.hasPrefix(Self.venueIdentifierPrefix) {
            return
        }

        Log.location.info("Geofence \(identifier, privacy: .public) \(inside ? "entered" : "left", privacy: .public)")
        // Woken in the background, iOS gives the app seconds before suspending
        // it again; ask for enough to get a fix and report it.
        await withBackgroundTime("Venue geofence") { await refreshPosition() }
    }

    /// Picks the regions to watch from `location`, downloading the venues'
    /// envelopes when they're missing or old. Does nothing while the device
    /// is still well inside the current re-center circle.
    private func planGeofences(around location: CLLocation) async {
        guard let monitor, isAuthorized, !isPlanningGeofences else { return }

        if let geofencePlan {
            let center = CLLocation(latitude: geofencePlan.recenterLatitude, longitude: geofencePlan.recenterLongitude)
            let fencesFresh = venueFencesFetchedAt.map { Date.now.timeIntervalSince($0) < Self.venueFencesMaxAge } ?? false
            if fencesFresh, location.distance(from: center) < geofencePlan.recenterRadius / 2 { return }
        }

        isPlanningGeofences = true
        defer { isPlanningGeofences = false }

        let position = Coordinates(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)

        if venueFencesFetchedAt.map({ Date.now.timeIntervalSince($0) >= Self.venueFencesMaxAge }) ?? true {
            do {
                venueFences = try await api.venueFences(near: position)
                venueFencesFetchedAt = .now
            } catch {
                Log.location.error("Venue envelopes failed: \(error.localizedDescription, privacy: .public)")
                // Try again on the next fix; keep watching what we had.
                if venueFencesFetchedAt == nil { return }
            }
        }

        let plan = GeofencePlan(around: position, venues: venueFences)
        await apply(plan, to: monitor)
        geofencePlan = plan
    }

    private func apply(_ plan: GeofencePlan, to monitor: CLMonitor) async {
        // The radius is part of the identifier, so a venue whose envelope
        // changed is replaced rather than kept.
        let wanted = Dictionary(
            plan.venues.map { ("\(Self.venueIdentifierPrefix)\($0.id.uuidString.lowercased()):\(Int($0.radius))", $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existing = Set(await monitor.identifiers)

        for identifier in existing where wanted[identifier] == nil {
            await monitor.remove(identifier)
        }

        for (identifier, fence) in wanted where !existing.contains(identifier) {
            await monitor.add(
                CLMonitor.CircularGeographicCondition(center: fence.center, radius: fence.radius),
                identifier: identifier,
                assuming: .unsatisfied
            )
        }

        await monitor.add(
            CLMonitor.CircularGeographicCondition(center: plan.recenterCenter, radius: plan.recenterRadius),
            identifier: Self.recenterIdentifier,
            assuming: .satisfied
        )

        Log.location.info("Watching \(wanted.count) venues, re-center radius \(Int(plan.recenterRadius))m")
    }

    // MARK: - Persistence

    private static func restoreLocale() -> AppLocale? {
        let defaults = UserDefaults.standard

        guard let idString = defaults.string(forKey: storedLocaleIDKey),
              let id = UUID(uuidString: idString),
              let name = defaults.string(forKey: storedLocaleNameKey) else { return nil }

        return AppLocale(id: id, name: name)
    }

    private static func persist(_ locale: AppLocale) {
        let defaults = UserDefaults.standard
        defaults.set(locale.id.uuidString, forKey: storedLocaleIDKey)
        defaults.set(locale.name, forKey: storedLocaleNameKey)
    }
}

// MARK: - Background time

/// Keeps the app running until `work` finishes when a geofence or a
/// significant change woke it in the background; without this iOS can
/// suspend it again before the position reaches the API. In the foreground
/// it costs nothing.
@MainActor
private func withBackgroundTime(_ name: String, _ work: @MainActor () async -> Void) async {
    let time = BackgroundTime(name)
    await work()
    time.end()
}

@MainActor
private final class BackgroundTime {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(_ name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

// MARK: - Core Location delegate

/// Core Location's delegate protocol predates Swift concurrency. The manager is
/// created on the main actor and therefore calls back on it, so the conformance
/// is marked `@preconcurrency` and the class pinned to `@MainActor` rather than
/// hopping queues by hand in every callback.
@MainActor
private final class Delegate: NSObject, @preconcurrency CLLocationManagerDelegate {
    weak var owner: LocationProvider?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        owner?.authorizationChanged(to: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        owner?.update(with: location)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didRange beacons: [CLBeacon],
        satisfying constraint: CLBeaconIdentityConstraint
    ) {
        owner?.update(beacons: beacons)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let owner else { return }
        Task { await owner.refreshLocale() }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Log.location.error("Core Location failed: \(error.localizedDescription, privacy: .public)")
        owner?.fixFailed()
    }
}
