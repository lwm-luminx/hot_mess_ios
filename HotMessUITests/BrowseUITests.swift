//
//  BrowseUITests.swift
//  HotMessUITests
//

import XCTest

/// Walks every tab and the detail screens they lead to with the session already on the
/// device, saving a screenshot of each, so a failing screen shows what it says. Skips when
/// signed out; FacebookSignInUITests signs in.
@MainActor
final class BrowseUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.useRunnerAPI()
        app.launch()

        if !app.descendants(matching: .any)["main.tabs"].waitForExistence(timeout: 15) {
            throw XCTSkip("Not signed in; run FacebookSignInUITests first")
        }
    }

    func testNow() {
        open(tab: "Now")
    }

    func testEventsAndEvent() throws {
        open(tab: "Events")
        try skipWithoutEvents()
        openFirstRow(as: "Event")
    }

    /// Picks each RSVP on the first event and puts the original back.
    func testRSVP() throws {
        open(tab: "Events")
        try skipWithoutEvents()
        guard openFirstRow(as: "Event") else { return }

        // Going and Interested are on the hero; Not going is in the options menu.
        let choices = ["Going", "Interested"]
        let original = choices.first { app.buttons[$0].isSelected }
        for choice in choices {
            let button = app.buttons[choice]
            guard button.waitForExistence(timeout: 5) else {
                XCTFail("The event has no \(choice) RSVP button")
                return
            }
            button.tap()
            sleep(2)
            if app.alerts["Couldn't Save RSVP"].exists {
                snapshot("RSVP \(choice) failed")
                XCTFail("RSVP \(choice) failed: \(app.alerts.firstMatch.staticTexts.allElementsBoundByIndex.map(\.label))")
                app.alerts.buttons.firstMatch.tap()
                return
            }
            XCTAssertTrue(button.isSelected, "\(choice) didn't stay selected")
        }

        let menu = app.buttons["event.optionsMenu"]
        if menu.waitForExistence(timeout: 5) {
            menu.tap()
            app.buttons["event.notGoing"].tap()
            sleep(2)
            XCTAssertFalse(app.alerts["Couldn't Save RSVP"].exists, "RSVP Not going failed")
            XCTAssertFalse(choices.contains { app.buttons[$0].isSelected }, "Not going left another RSVP selected")
        }
        snapshot("RSVP")
        if let original { app.buttons[original].tap() }
    }

    func testVenuesAndVenue() {
        open(tab: "Venues")
        openFirstRow(as: "Venue")
    }

    func testPeopleAndPerson() {
        open(tab: "People")
        openFirstRow(as: "Person")
    }

    func testMe() {
        open(tab: "Me")
    }

    // MARK: - Helpers

    /// An empty Events tab is the locale having nothing on, not a failure.
    private func skipWithoutEvents() throws {
        // The listing waits on the locale, which waits on a location fix.
        if app.staticTexts["No Events"].waitForExistence(timeout: 10) {
            throw XCTSkip("Nothing is scheduled in the device's locale")
        }
    }

    private let tabs = ["Now", "Events", "Venues", "People", "Me"]

    private func open(tab: String) {
        let button = app.tabBars.buttons[tab]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "There's no \(tab) tab")
        button.tap()
        settle(as: tab)
    }

    /// Taps the first row that pushes a screen, and checks that screen.
    @discardableResult
    private func openFirstRow(as screen: String) -> Bool {
        // Not the tab bar, which on iOS 26 is also a collection of buttons.
        let row = app.collectionViews.buttons.matching(NSPredicate(format: "NOT (label IN %@)", tabs)).firstMatch
        guard row.waitForExistence(timeout: 10) else {
            XCTFail("Nothing to open for \(screen)")
            return false
        }
        row.tap()
        return settle(as: screen)
    }

    /// Waits for the spinner to go, saves a screenshot and fails on LoadState's error view.
    @discardableResult
    private func settle(as screen: String) -> Bool {
        let spinner = app.activityIndicators.firstMatch
        let deadline = Date().addingTimeInterval(20)
        while spinner.exists, Date() < deadline { usleep(250_000) }
        sleep(1)
        snapshot(screen)

        let failure = app.staticTexts["Something went wrong"]
        guard failure.exists else { return true }
        let detail = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { $0 != "Something went wrong" }
        XCTFail("\(screen) shows an error: \(detail.joined(separator: " / "))")
        return false
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
