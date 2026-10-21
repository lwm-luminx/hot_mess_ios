//
//  AboutUpdateTests.swift
//  HotMessTests
//

import AudienceKit
import Foundation
import Testing

@testable import HotMess

@Suite("About: updates")
struct AboutUpdateTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private let locale = Locale(identifier: "en_US")

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test("Last checked this week is the weekday and time")
    func lastCheckedThisWeek() {
        // Monday 19 October 2026, 9:14pm.
        let text = AboutUpdateRows.lastChecked(date(19, 21, 14), now: date(20, 10, 0), calendar: calendar,
                                               locale: locale)

        #expect(text == "Mon 9:14pm")
    }

    @Test("Last checked longer ago is the date")
    func lastCheckedEarlier() {
        let text = AboutUpdateRows.lastChecked(date(2, 9, 0), now: date(20, 10, 0), calendar: calendar,
                                               locale: locale)

        #expect(text == "Oct 2")
    }

    @Test("The footnote names the channel, and development builds get none")
    func footnote() {
        #expect(AboutUpdateRows.footnote(for: .testFlight)
            == "We check for a new beta when you open Hot Mess, at most once a day.")
        #expect(AboutUpdateRows.footnote(for: .appStore)
            == "We check for updates when you open Hot Mess, at most once a day.")
        #expect(AboutUpdateRows.footnote(for: .development) == nil)
        #expect(AboutUpdateRows.footnote(for: nil) == nil)
    }

    @Test("The SDK's update rules see this build's numeric CFBundleVersion")
    func buildNumber() {
        let configuration = AppConfiguration(baseURL: AppConfiguration.defaultBaseURL, version: "2.1", build: 420_212)
        let release = AppRelease(appStoreID: "1195758383",
                                 testFlight: .init(latestBuild: 420_215, minimumBuild: 420_180))

        let prompt = UpdateRules.prompt(source: .testFlight, release: release,
                                        currentBuild: configuration.build, currentVersion: configuration.version,
                                        dismissedBuild: nil, canOpenTestFlight: true)

        #expect(prompt?.isBlocking == false)
        #expect(prompt?.offer.latestLabel == "Build 420215")
    }
}
