//
//  CacheRefresher.swift
//  HotMess
//

import AudienceKit
import BackgroundTasks
import Foundation

/// Keeps what the screens read fresh in the on-device GraphQL cache, so a
/// flaky connection or a failing API shows the last good data instead of an
/// error.
///
/// Which cities to refresh comes from the locales the person has been in
/// lately (``VisitedLocales``), remembered on the phone only and never sent.
/// It runs as a background app refresh (`BGAppRefreshTask`), when the app
/// comes to the foreground, and when a geofence wakes it. After a failure it
/// waits longer each time (``RefreshBackoff``, 15 minutes doubling to 6
/// hours) and never retries in a loop; the cache keeps serving meanwhile.
@MainActor
final class CacheRefresher {
    static let taskIdentifier = "social.hotmess.HotMess.refresh"
    private static let backoffKey = "HotMess.cacheRefreshBackoff"
    /// No more than this many cities per run.
    private static let localeLimit = 3

    let visited: VisitedLocales
    private let api: HotMessAPI
    private let audienceKit: AudienceKitClient
    private let isSignedIn: @MainActor () -> Bool
    private var running: Task<Bool, Never>?
    private var backoff: RefreshBackoff {
        didSet { Self.save(backoff) }
    }

    init(api: HotMessAPI, audienceKit: AudienceKitClient, audienceID: String?,
         isSignedIn: @escaping @MainActor () -> Bool) {
        self.api = api
        self.audienceKit = audienceKit
        self.isSignedIn = isSignedIn
        visited = VisitedLocales(audienceID: audienceID ?? "hotmess")
        backoff = Self.loadBackoff()
    }

    /// Notes that the person is in `locale`, so its data is kept fresh.
    func recordVisit(_ locale: AppLocale) {
        visited.record(id: locale.id.uuidString, name: locale.name)
    }

    // MARK: - Background task

    /// Registers the background refresh. Must run before launch finishes.
    func register() {
        // Delivered on the main queue, where this class lives.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self, let refresh = task as? BGAppRefreshTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.run(SystemTask(task: refresh))
            }
        }
    }

    /// Asks iOS for the next background refresh, no sooner than the backoff
    /// allows. iOS decides when it actually runs.
    func schedule() {
        guard isSignedIn(), !visited.recent().isEmpty else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = max(backoff.nextDate(), Date.now.addingTimeInterval(backoff.base))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Log.network.error("Couldn't schedule the cache refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The system's task, carried into the refresh. BackgroundTasks marks it
    /// thread-safe for completion and expiry, but not `Sendable`.
    private struct SystemTask: @unchecked Sendable {
        let task: BGAppRefreshTask
    }

    private func run(_ system: SystemTask) {
        let work = Task { @MainActor in await refresh(force: true) }
        system.task.expirationHandler = { work.cancel() }
        Task { @MainActor in
            let succeeded = await work.value
            schedule()
            system.task.setTaskCompleted(success: succeeded)
        }
    }

    // MARK: - Refresh

    /// Refreshes the cities visited lately when the backoff says it's due
    /// (`force` skips the wait, for the system's background task). A refresh
    /// already running is joined, not repeated. True when it succeeded.
    @discardableResult
    func refresh(force: Bool = false) async -> Bool {
        if let running { return await running.value }
        guard isSignedIn(), force || backoff.isDue() else { return false }
        let locales = visited.recent().prefix(Self.localeLimit).compactMap { UUID(uuidString: $0.id) }
        guard !locales.isEmpty else { return false }

        let task = Task { @MainActor [api, audienceKit] () -> Bool in
            var succeeded = true
            for localeID in locales {
                guard !Task.isCancelled else { return false }
                do {
                    _ = try await api.eventList(in: localeID, cachePolicy: .refresh)
                } catch {
                    succeeded = false
                    Log.network.error("Cache refresh failed: \(error.localizedDescription, privacy: .public)")
                    // The API is failing: stop here rather than ask again.
                    break
                }
            }
            // Venues are audience-wide; the screens fall back to the last list
            // on their own, so a failure here doesn't count.
            if succeeded { _ = try? await audienceKit.venues() }
            // Friends' Pings for the Tonight widget, which only shows what
            // the app last saved.
            if succeeded, let pings = try? await api.pings() {
                TonightWidget.update(myPing: pings.myPing, friendPings: pings.friendPings)
            }
            return succeeded
        }
        running = task
        let succeeded = await task.value
        running = nil
        if !Task.isCancelled {
            if succeeded { backoff.succeeded() } else { backoff.failed() }
        }
        return succeeded
    }

    /// Forgets the cities and the backoff on sign-out. The SDK empties the
    /// cache itself.
    func forget() {
        running?.cancel()
        visited.removeAll()
        backoff = RefreshBackoff()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    }

    // MARK: - Persistence

    private static func loadBackoff() -> RefreshBackoff {
        guard let data = UserDefaults.standard.data(forKey: backoffKey),
              let backoff = try? JSONDecoder().decode(RefreshBackoff.self, from: data) else { return RefreshBackoff() }
        return backoff
    }

    private static func save(_ backoff: RefreshBackoff) {
        guard let data = try? JSONEncoder().encode(backoff) else { return }
        UserDefaults.standard.set(data, forKey: backoffKey)
    }
}
