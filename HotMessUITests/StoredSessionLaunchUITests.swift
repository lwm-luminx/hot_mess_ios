//
//  StoredSessionLaunchUITests.swift
//  HotMessUITests
//

import XCTest

/// Signs in with the App Review code, then relaunches with the stored session, which is how people open the app
/// every day. iOS kills an app that takes more than about 20 seconds to show its first scene, so the relaunch has to
/// reach the tabs well within that and stay responsive.
@MainActor
final class StoredSessionLaunchUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testRelaunchWithStoredSession() throws {
        let environment = ProcessInfo.processInfo.environment
        let code = environment["HOTMESS_UITEST_REVIEW_CODE"] ?? ""
        try XCTSkipIf(code.isEmpty || !XCUIApplication.hasRunnerAPI,
                      "Runs under scripts/ui-tests.py with HOTMESS_UITEST_REVIEW_CODE")

        let app = XCUIApplication()
        app.launchArguments = ["-HotMessUITestSignedOut"]
        app.useRunnerAPI()
        app.launch()

        let review = app.buttons["login.reviewCode"]
        XCTAssertTrue(review.waitForExistence(timeout: 15), "The login screen offers no review code")
        app.agreeToLoginTerms()
        review.tap()
        let field = app.textFields["reviewCode.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The review code sheet didn't open")
        field.tap()
        field.typeText(code)
        app.buttons["reviewCode.submit"].tap()

        let tabs = app.descendants(matching: .any)["main.tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 30), "Signing in with the review code didn't reach the tabs")
        snapshot("Signed in")
        sleep(10) // Let the first session load and subscribe, as a real one does before the user leaves.
        app.terminate()

        // The everyday launch: a stored session, no launch arguments.
        let relaunch = XCUIApplication()
        relaunch.useRunnerAPI()
        let started = Date()
        relaunch.launch()
        let relaunchedTabs = relaunch.descendants(matching: .any)["main.tabs"]
        XCTAssertTrue(relaunchedTabs.waitForExistence(timeout: 20), "The relaunch didn't reach the tabs within 20s")
        snapshot("Relaunched after \(Int(Date().timeIntervalSince(started)))s")

        // Responsive, not just drawn: switching tabs has to work for a while after launch.
        for _ in 0..<3 {
            for tab in ["Events", "Venues", "Now"] {
                let button = relaunch.tabBars.buttons[tab]
                if button.exists { button.tap() }
            }
            sleep(5)
        }
        XCTAssertEqual(relaunch.state, .runningForeground, "Hot Mess stopped running after the relaunch")
        snapshot("Still running")
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
