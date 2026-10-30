//
//  PositionTrackerTests.swift
//  HotMessTests
//

import Foundation
import Testing

@testable import HotMess

@Suite("Pretend I'm here")
struct PositionTrackerTests {
    private let nyne = Coordinates(latitude: 47.6575451, longitude: -117.414777)

    @Test("Reports the device's position with its beacon")
    func devicePosition() {
        var tracker = PositionTracker(simulationAllowed: false)
        // #expect can't call mutating methods, so each result is taken first.
        let beaconWithoutFix = tracker.beacon(major: 1, minor: 2)
        #expect(!beaconWithoutFix, "no beacon without a position")

        let firstFix = tracker.deviceFix(latitude: 47.61, longitude: -122.32)
        #expect(firstFix)
        let firstBeacon = tracker.beacon(major: 1, minor: 2)
        #expect(firstBeacon)
        let sameBeacon = tracker.beacon(major: 1, minor: 2)
        #expect(!sameBeacon, "the same beacon again changes nothing")
        let secondFix = tracker.deviceFix(latitude: 47.62, longitude: -122.33)
        #expect(secondFix)

        #expect(tracker.current == Coordinates(latitude: 47.62, longitude: -122.33, beaconMajor: 1, beaconMinor: 2))
    }

    @Test("Reports the venue while pretending, then the latest real position")
    func pretending() {
        var tracker = PositionTracker(simulationAllowed: true)
        tracker.deviceFix(latitude: 47.61, longitude: -122.32)

        let started = tracker.simulate(latitude: nyne.latitude, longitude: nyne.longitude, venueName: "Nyne")
        #expect(started)
        #expect(tracker.current == nyne)
        #expect(tracker.simulatedVenueName == "Nyne")

        let fixWhilePretending = tracker.deviceFix(latitude: 47.70, longitude: -122.40)
        #expect(!fixWhilePretending, "device fixes aren't reported while pretending")
        let beaconWhilePretending = tracker.beacon(major: 3, minor: 4)
        #expect(!beaconWhilePretending)
        #expect(tracker.current == nyne)

        let stopped = tracker.stopSimulating()
        #expect(stopped)
        #expect(tracker.simulatedVenueName == nil)
        #expect(tracker.current == Coordinates(latitude: 47.70, longitude: -122.40, beaconMajor: 3, beaconMinor: 4))
        let stoppedAgain = tracker.stopSimulating()
        #expect(!stoppedAgain)
    }

    @Test("Pretends outside a test build only when App Review allows it")
    func appReview() {
        var tracker = PositionTracker(simulationAllowed: false)

        let refused = tracker.simulate(latitude: nyne.latitude, longitude: nyne.longitude, venueName: "Nyne")
        #expect(!refused)
        #expect(tracker.current == nil)

        let allowed = tracker.simulate(latitude: nyne.latitude, longitude: nyne.longitude, venueName: "Nyne",
                                       allowed: true)
        #expect(allowed)
        #expect(tracker.current == nyne)
    }

    @Test("Reports nothing after stopping when there's no real fix yet")
    func stopWithoutFix() {
        var tracker = PositionTracker(simulationAllowed: true)
        tracker.simulate(latitude: nyne.latitude, longitude: nyne.longitude, venueName: "Nyne")
        tracker.stopSimulating()

        #expect(tracker.current == nil)
    }

    @Test("Store builds can't pretend")
    func storeBuilds() {
        var tracker = PositionTracker(simulationAllowed: false)
        tracker.deviceFix(latitude: 47.61, longitude: -122.32)

        let started = tracker.simulate(latitude: nyne.latitude, longitude: nyne.longitude, venueName: "Nyne")
        #expect(!started)
        #expect(tracker.simulatedVenueName == nil)
        #expect(tracker.current == Coordinates(latitude: 47.61, longitude: -122.32))
    }

    @Test("Only staging and debug builds and beta installs are test builds")
    func testBuilds() {
        let base = URL(string: "https://api.audiencekit.com")!
        #expect(AppConfiguration(baseURL: base, environment: .staging).isTestBuild)
        #expect(AppConfiguration(baseURL: base, isBetaInstall: true).isTestBuild)
        #if !DEBUG
        #expect(!AppConfiguration(baseURL: base, environment: .production).isTestBuild)
        #endif
    }

    @Test("Beta installs wear the ribbon for their server; everything else the primary icon")
    func betaIcons() {
        let next = URL(string: AppConfiguration.APIServer.next.baseURL)!
        let production = URL(string: AppConfiguration.APIServer.production.baseURL)!
        #expect(AppConfiguration(baseURL: next, isBetaInstall: true).alternateIconName == "AppIconNext")
        #expect(AppConfiguration(baseURL: production, isBetaInstall: true).alternateIconName == "AppIconBeta")
        #expect(AppConfiguration(baseURL: production).alternateIconName == nil)
        #expect(AppConfiguration(baseURL: next).alternateIconName == nil)
    }

    @Test("A super admin's App Store install can switch servers and wears the Next ribbon only on next")
    func superAdminSwitch() {
        let next = URL(string: AppConfiguration.APIServer.next.baseURL)!
        let production = URL(string: AppConfiguration.APIServer.production.baseURL)!
        #expect(AppConfiguration(baseURL: production, isBetaInstall: true).canSwitchServer)
        #expect(!AppConfiguration(baseURL: production).canSwitchServer)
        #expect(AppConfiguration(baseURL: next, canSwitchServer: true).alternateIconName == "AppIconNext")
        #expect(AppConfiguration(baseURL: production, canSwitchServer: true).alternateIconName == nil)
    }
}
