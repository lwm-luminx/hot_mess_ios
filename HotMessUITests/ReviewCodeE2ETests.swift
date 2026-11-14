//
//  ReviewCodeE2ETests.swift
//  HotMessUITests
//
//  End to end against a LOCAL fixture API, signed in with an App Review code: Now, an event and an RSVP that sticks,
//  a venue, People, Me, signing out, and a wrong code that stays signed out.
//
//  Skipped unless both are set, as TEST_RUNNER_<name>=… on the xcodebuild command line (Scripts/review-e2e.sh does it):
//
//    HOTMESS_E2E_API_URL      the local API, e.g. http://127.0.0.1:3917 (audience_kit_api in RAILS_ENV=test after
//                             `rails ui_tests:setup`, which puts the hotmess audience in App Review with The Test Bar)
//    HOTMESS_E2E_REVIEW_CODE  the code that API was set up with (AK_REVIEW_CODE); never the real App Store code
//
//  Only a localhost API is accepted: api.next.audiencekit.com shares the production database. Nothing here deletes
//  an account, blocks or reports anyone.
//

import CoreLocation
import XCTest

@MainActor
final class ReviewCodeE2ETests: XCTestCase {
    /// Where the fixture's The Test Bar is (AppReviewVenue::DEMO_POINT), so the venue and its events are nearby.
    static let fixturePoint = CLLocation(latitude: 37.7793, longitude: -122.4194)
    static let venue = "The Test Bar"

    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        let api = try Self.localAPI()
        app = XCUIApplication()
        app.launchArguments = ["-HotMessUITestSignedOut"]
        app.launchEnvironment["HOTMESS_API_URL"] = api.absoluteString
        addUIInterruptionMonitor(withDescription: "Location and notification prompts") { alert in
            for label in ["Allow While Using App", "Allow Once", "Keep Only While Using", "Don’t Allow", "Don't Allow"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); return true }
            }
            return false
        }
        XCUIDevice.shared.location = XCUILocation(location: Self.fixturePoint)
    }

    func testWrongCodeShowsTheErrorAndStaysSignedOut() throws {
        _ = try Self.code()
        app.launch()
        enterCode("WRONG0WRONG0WRONG")
        XCTAssertTrue(app.alerts["Sign In Failed"].waitForExistence(timeout: 20), "A wrong code didn't say so")
        app.alerts["Sign In Failed"].buttons["OK"].tap()
        XCTAssertFalse(tabs.exists, "A wrong code signed in")
        XCTAssertTrue(app.buttons["login.reviewCode"].waitForExistence(timeout: 10), "The sign-in screen went away")
    }

    func testReviewerJourney() throws {
        let code = try Self.code()
        app.launch()
        enterCode(code)
        XCTAssertTrue(tabs.waitForExistence(timeout: 30), "The review code didn't sign in")
        // Lets the interruption monitor answer a location or notification prompt. The tap goes on the status bar's
        // strip: the middle of Now has "Connect Facebook", which would open Facebook's sign-in page.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.01)).tap()

        // Nothing opened Facebook (the e2e run must stay on the local API).
        XCTAssertFalse(app.webViews.firstMatch.exists, "A web page opened over the app")

        // Now loads: its Ping button and no error.
        open(tab: "Now")
        XCTAssertTrue(app.buttons["Ping"].waitForExistence(timeout: 20), "Now didn't load")
        XCTAssertFalse(app.staticTexts["Something went wrong"].exists, "Now failed to load")

        // Events opens an event, and an RSVP sticks across leaving and reopening it.
        open(tab: "Events")
        let event = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "card.event.")).firstMatch
        XCTAssertTrue(scroll(to: event), "Events listed no event; is the simulator at the fixture venue?")
        let eventID = event.identifier
        event.tap()
        let interested = app.buttons["Interested"]
        let going = app.buttons["Going"]
        XCTAssertTrue(going.waitForExistence(timeout: 20), "The event's RSVP buttons didn't show")
        let choice = going.isSelected ? interested : going
        let label = choice.label
        choice.tap()
        XCTAssertTrue(wait(for: app.buttons[label], selected: true), "\(label) didn't take")
        XCTAssertFalse(app.alerts["Couldn't Save RSVP"].exists, "The API refused the RSVP")
        back()
        let again = app.buttons[eventID]
        XCTAssertTrue(scroll(to: again), "The event went missing from Events")
        again.tap()
        XCTAssertTrue(wait(for: app.buttons[label], selected: true), "\(label) didn't stick after reopening the event")
        back()

        // Venues opens the fixture venue, with what's coming up there.
        open(tab: "Venues")
        let venue = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
                                                     "card.venue.", Self.venue)).firstMatch
        XCTAssertTrue(scroll(to: venue), "\(Self.venue) isn't in Venues")
        venue.tap()
        let comingUp = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Coming Up", "Tonight's lineup",
                                                                                   "Tonight"])).firstMatch
        XCTAssertTrue(scroll(to: comingUp), "\(Self.venue)'s page showed neither its lineup nor what's coming up")
        back()

        // People and Me load.
        open(tab: "People")
        XCTAssertFalse(app.staticTexts["Something went wrong"].waitForExistence(timeout: 5), "People failed to load")
        open(tab: "Me")
        let signOut = app.buttons["Sign Out"]
        XCTAssertTrue(scroll(to: signOut), "Me didn't load (no Sign Out)")

        // Signing out returns to the sign-in screen.
        signOut.tap()
        let confirm = app.alerts.buttons["Sign Out"].exists ? app.alerts.buttons["Sign Out"] : app.sheets.buttons["Sign Out"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        XCTAssertTrue(app.buttons["login.reviewCode"].waitForExistence(timeout: 20), "Sign Out didn't return to sign-in")
        XCTAssertFalse(tabs.exists)
    }

    // MARK: - Steps

    private var tabs: XCUIElement { app.descendants(matching: .any)["main.tabs"] }

    private func enterCode(_ code: String) {
        let reviewCode = app.buttons["login.reviewCode"]
        XCTAssertTrue(reviewCode.waitForExistence(timeout: 30),
                      "\"Have an App Review code?\" didn't show; is App Review on for the local hotmess audience?")
        for id in ["login.eulaCheckbox", "login.ageCheckbox"] {
            let box = app.buttons[id]
            if box.exists && box.value as? String != "1" { box.tap() }
        }
        reviewCode.tap()
        let field = app.textFields["reviewCode.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The App Review code sheet didn't open")
        field.tap()
        field.typeText(code)
        app.buttons["reviewCode.submit"].tap()
    }

    private func open(tab name: String) {
        // The tab bar's button, waited for: Now has an "Events" section header of the same name further down.
        let phoneTab = app.tabBars.buttons[name]
        let button = phoneTab.waitForExistence(timeout: 10) ? phoneTab
            : app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "The \(name) tab didn't appear")
        button.tap()
        settle()
    }

    private func back() {
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
        settle()
    }

    private func wait(for element: XCUIElement, selected: Bool, timeout: TimeInterval = 15) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND selected == %@", NSNumber(value: selected))
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
                              timeout: timeout) == .completed
    }

    private func scroll(to element: XCUIElement) -> Bool {
        if element.waitForExistence(timeout: 10), element.isHittable { return true }
        for _ in 0..<10 {
            if element.exists && element.isHittable { return true }
            app.swipeUp(velocity: .slow)
        }
        return element.exists && element.isHittable
    }

    private func settle() {
        let spinner = app.activityIndicators.firstMatch
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: spinner)
        _ = XCTWaiter.wait(for: [finished], timeout: 20)
    }

    // MARK: - Configuration

    private static func value(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The local API, or a skip. Anything but localhost is refused outright, never just skipped quietly.
    static func localAPI() throws -> URL {
        guard let raw = value("HOTMESS_E2E_API_URL") else {
            throw XCTSkip("Set TEST_RUNNER_HOTMESS_E2E_API_URL (a local fixture API) and TEST_RUNNER_HOTMESS_E2E_REVIEW_CODE to run this.")
        }
        guard let url = URL(string: raw), let host = url.host, ["127.0.0.1", "localhost", "::1"].contains(host) else {
            XCTFail("HOTMESS_E2E_API_URL must be a local API (127.0.0.1 or localhost), not \(raw)")
            throw XCTSkip("Not a local API")
        }
        return url
    }

    static func code() throws -> String {
        guard let code = value("HOTMESS_E2E_REVIEW_CODE") else {
            throw XCTSkip("Set TEST_RUNNER_HOTMESS_E2E_REVIEW_CODE (the local API's AK_REVIEW_CODE) to run this.")
        }
        return code
    }
}
