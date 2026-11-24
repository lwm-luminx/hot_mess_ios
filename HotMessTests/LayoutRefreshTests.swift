//
//  LayoutRefreshTests.swift
//  HotMessTests
//

import AudienceKit
import Foundation
import Testing

@testable import HotMess

@Suite("Card layout refresh")
struct LayoutRefreshPolicyTests {
    private let start = ContinuousClock.now
    private let locale = UUID()
    private let nyne = Coordinates(latitude: 47.6575451, longitude: -117.414777)

    private func north(_ metres: Double, beaconMajor: Int? = nil) -> Coordinates {
        Coordinates(latitude: nyne.latitude + metres / 111_320, longitude: nyne.longitude, beaconMajor: beaconMajor)
    }

    private func at(_ seconds: Int) -> ContinuousClock.Instant { start + .seconds(seconds) }

    private func request(_ coordinates: Coordinates?) -> LayoutRefreshPolicy.Request {
        .init(coordinates: coordinates, localeID: locale)
    }

    @Test("The first ask is always due")
    func first() {
        #expect(LayoutRefreshPolicy().isDue(request(nyne), at: start))
    }

    @Test("A good layout isn't asked for again until refreshAfter, however the fix jitters")
    func freshLayout() {
        var policy = LayoutRefreshPolicy()
        policy.asked(request(nyne), at: start)
        policy.succeeded(refreshAfter: 60, at: start)

        for second in 1..<60 {
            #expect(!policy.isDue(request(north(Double(second % 20))), at: at(second)))
        }
        #expect(policy.isDue(request(nyne), at: at(60)))
    }

    @Test("A refreshAfter of zero still waits the minimum")
    func zeroRefreshAfter() {
        var policy = LayoutRefreshPolicy()
        policy.asked(request(nyne), at: start)
        policy.succeeded(refreshAfter: 0, at: start)

        #expect(!policy.isDue(request(nyne), at: at(1)))
        #expect(policy.isDue(request(nyne), at: at(15)))
    }

    @Test("A real move asks again, but not more than once per spacing")
    func movedFar() {
        var policy = LayoutRefreshPolicy()
        policy.asked(request(nyne), at: start)
        policy.succeeded(refreshAfter: 600, at: start)

        #expect(!policy.isDue(request(north(500)), at: at(10)))
        #expect(policy.isDue(request(north(500)), at: at(30)))
        #expect(!policy.isDue(request(north(100)), at: at(30)))
    }

    @Test("Another locale asks at once, but not more than once per locale spacing")
    func changedLocale() {
        var policy = LayoutRefreshPolicy()
        policy.asked(request(nyne), at: start)
        policy.succeeded(refreshAfter: 600, at: start)

        #expect(!policy.isDue(.init(coordinates: nyne, localeID: UUID()), at: at(1)))
        #expect(policy.isDue(.init(coordinates: nyne, localeID: UUID()), at: at(5)))
    }

    @Test("Another beacon asks again only once per spacing, however often ranging flips")
    func changedBeacon() {
        var policy = LayoutRefreshPolicy()
        policy.asked(request(north(0, beaconMajor: 3)), at: start)
        policy.succeeded(refreshAfter: 600, at: start)

        for second in 1..<30 {
            let major = second.isMultiple(of: 2) ? 3 : 7
            #expect(!policy.isDue(request(north(0, beaconMajor: major)), at: at(second)))
        }
        #expect(policy.isDue(request(north(0, beaconMajor: 7)), at: at(30)))
        #expect(!policy.isDue(request(north(0, beaconMajor: 3)), at: at(30)))
    }

    @Test("Failures back off, doubling up to the cap, wherever the device goes")
    func backoff() {
        var policy = LayoutRefreshPolicy()
        #expect(policy.backoff(after: 1) == .seconds(15))
        #expect(policy.backoff(after: 2) == .seconds(30))
        #expect(policy.backoff(after: 3) == .seconds(60))
        #expect(policy.backoff(after: 20) == .seconds(600))

        policy.asked(request(nyne), at: start)
        policy.failed(at: start)
        #expect(!policy.isDue(request(nyne), at: at(1)))
        #expect(!policy.isDue(.init(coordinates: north(5_000), localeID: UUID()), at: at(14)))
        #expect(policy.isDue(request(nyne), at: at(15)))

        policy.asked(request(nyne), at: at(15))
        policy.failed(at: at(15))
        #expect(!policy.isDue(request(nyne), at: at(44)))
        #expect(policy.isDue(request(nyne), at: at(45)))

        policy.asked(request(nyne), at: at(45))
        policy.succeeded(refreshAfter: 60, at: at(45))
        #expect(!policy.isBackingOff)
        #expect(!policy.isDue(request(nyne), at: at(100)))
    }

    @Test("A person's refresh is always due, even backing off")
    func forced() {
        var policy = LayoutRefreshPolicy()
        policy.asked(request(nyne), at: start)
        policy.failed(at: start)
        #expect(policy.isDue(request(nyne), at: at(1), force: true))
    }
}

/// A clock the test moves by hand.
final class ManualClock: @unchecked Sendable {
    var now = ContinuousClock.now
    func advance(_ seconds: Int) { now += .seconds(seconds) }
}

@Suite("Screen layout loading")
@MainActor
struct ScreenLayoutLoadTests {
    private let nyne = Coordinates(latitude: 47.6575451, longitude: -117.414777)
    private let locale = UUID()

    private func layout(clock: ManualClock, calls: Counter, delay: Duration = .zero,
                        succeeds: @escaping @Sendable () -> Bool) -> ScreenLayout {
        ScreenLayout(fallback: ["builtIn"], now: { clock.now }, fetch: { _, _, _ in
            _ = calls.increment()
            if delay > .zero { try? await Task.sleep(for: delay) }
            return succeeds()
                ? CardLayout(id: "server", cards: [], refreshAfter: 60)
                : .fallback(["builtIn"])
        })
    }

    @Test("A slow or failing server isn't asked again on every refresh")
    func failingServerBacksOff() async {
        let clock = ManualClock(), calls = Counter()
        let screen = layout(clock: clock, calls: calls) { false }

        for _ in 0..<50 {
            await screen.load(coordinates: nyne, localeID: locale)
            clock.advance(1)
        }
        // 50 seconds of refreshes: the first ask, then one after 15 s and one after another 30 s.
        #expect(calls.count == 3)
        #expect(screen.layout.isFallback)
    }

    @Test("Concurrent loads share one ask")
    func concurrentLoadsShareOneAsk() async {
        let clock = ManualClock(), calls = Counter()
        let screen = layout(clock: clock, calls: calls, delay: .milliseconds(100)) { true }

        async let first: Void = screen.load(coordinates: nyne, localeID: locale, force: true)
        async let second: Void = screen.load(coordinates: nyne, localeID: locale, force: true)
        async let third: Void = screen.load(coordinates: nyne, localeID: locale)
        _ = await (first, second, third)

        #expect(calls.count == 1)
        #expect(screen.layout.id == "server")
    }

    @Test("A failure keeps the server's last order")
    func failureKeepsLastGoodLayout() async {
        let clock = ManualClock(), calls = Counter()
        let succeed = LockedFlag(true)
        let screen = layout(clock: clock, calls: calls) { succeed.value }

        await screen.load(coordinates: nyne, localeID: locale)
        #expect(screen.layout.id == "server")

        succeed.value = false
        await screen.load(coordinates: nyne, localeID: locale, force: true)
        #expect(calls.count == 2)
        #expect(screen.layout.id == "server")
    }
}
