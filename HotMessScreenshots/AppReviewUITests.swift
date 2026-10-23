//
//  AppReviewUITests.swift
//  HotMessUITests
//

import XCTest

/// Walks the screens Meta's App Review needs to see, at a pace a reviewer can follow, for a screen
/// recording of the run. Xcode keeps the recording in the result bundle when the test plan or
/// .xctestrun keeps attachments.
///
/// Run them with the Screenshots scheme (Staging): `-HotMessUseNextAPI` and the other launch-argument
/// hooks only exist in builds with the `TEST_HOOKS` compilation condition (Debug and Staging).
@MainActor
final class AppReviewUITests: XCTestCase {
    private var facebook: XCUIApplication { XCUIApplication(bundleIdentifier: "com.facebook.Facebook") }
    private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }
    private var app: XCUIApplication!

    /// How long each screen stays up for the recording.
    private let dwell: UInt32 = 4

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-HotMessUITestSignedOut", "-HotMessUseNextAPI"]
        app.launch()
    }

    /// public_profile and email: Continue with Facebook, Facebook's dialog, then signed in.
    func testSignInWalkthrough() throws {
        try signInFromLoginScreen()
        showNotificationPrompt()
        open(tab: "Now")
        sleep(dwell)
        open(tab: "Me")
        sleep(dwell)
        // XCUITest quits the app when the test ends; hold the last screen for the recording.
        sleep(dwell * 3)
    }

    /// user_friends: where friends show up (Now, a venue's Friends Here, its chat room, and Ping).
    func testUserFriendsWalkthrough() throws {
        try signInFromLoginScreen()
        showNotificationPrompt()
        showNow()
        showFriendVenue()
        showPing()
        sleep(dwell * 3)
    }

    /// Sign in with Apple walkthrough using Sandbox Apple ID for screen recording and demo videos.
    func testAppleSignInWalkthrough() throws {
        try signInWithAppleFromLoginScreen()
        showNotificationPrompt()
        open(tab: "Now")
        sleep(dwell)
        open(tab: "Me")
        sleep(dwell)
        sleep(dwell * 3)
    }

    // MARK: - Sign-in

    private func signInWithAppleFromLoginScreen() throws {
        let appleButton = app.buttons["login.apple"]
        XCTAssertTrue(appleButton.waitForExistence(timeout: 15), "The Apple sign-in button didn't appear")
        snapshot("Login screen")
        sleep(dwell)

        let helper = AppleSignInHelper(app: app, dwell: dwell)
        try helper.signIn()
        snapshot("Signed in with Apple")
        sleep(dwell)
    }

    private func signInFromLoginScreen() throws {
        let login = app.buttons["login.facebook"]
        XCTAssertTrue(login.waitForExistence(timeout: 15), "The login screen didn't appear")
        sleep(dwell)
        login.tap()
        try signIn()
        sleep(dwell)
    }

    /// Taps through iOS's permission and Facebook's dialog, pausing on Facebook's screen so what it
    /// asks for is readable. Stops when Hot Mess shows its tabs.
    private func signIn() throws {
        let tabs = app.descendants(matching: .any)["main.tabs"]
        let continuing = NSPredicate(format: "label BEGINSWITH[c] 'Continue' OR label ==[c] 'Save' OR label ==[c] 'Got it'")
        var dialogShown = false
        let deadline = Date().addingTimeInterval(180)

        while !tabs.exists, Date() < deadline {
            if app.alerts["Sign In Failed"].exists {
                snapshot("Sign-in failed")
                XCTFail("Sign in failed: \(app.alerts.firstMatch.label)")
                return
            }
            let permission = [
                springboard.alerts.buttons["Continue"],
                app.alerts.buttons["Continue"],
            ].first { $0.exists && $0.isHittable }
            if let permission {
                sleep(2)
                permission.tap()
                sleep(2)
                continue
            }
            var buttons = [app.webViews.buttons.matching(continuing).firstMatch]
            if facebook.state == .runningForeground {
                buttons.append(facebook.buttons.matching(continuing).firstMatch)
            }
            if let button = buttons.first(where: { $0.exists && $0.isHittable }) {
                if !dialogShown {
                    dialogShown = true
                    snapshot("Facebook dialog")
                    sleep(dwell * 2)
                }
                button.tap()
                sleep(3)
                continue
            }
            sleep(1)
        }
        XCTAssertTrue(tabs.exists, "Hot Mess didn't reach its tabs after Facebook")
        snapshot("Signed in")
    }

    /// iOS asks for notifications after sign-in; leave it up for a moment, then allow.
    private func showNotificationPrompt() {
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) {
            sleep(2)
            allow.tap()
            sleep(2)
        }
    }

    // MARK: - Where friends show up

    /// Now: friends going out tonight, friends here, and where your friends are.
    /// Scrolls down Now once, pausing on each friends section on the way, then back to the top.
    /// Searching for each section separately kept swiping at the bottom of the page when it wasn't there.
    private func showNow() {
        open(tab: "Now")
        sleep(dwell)
        var shown = Set<String>()
        for _ in 0..<3 {
            for title in ["Friends going out tonight", "Friends here", "Where your friends are"]
            where !shown.contains(title) && app.staticTexts[title].isHittable {
                shown.insert(title)
                snapshot(title)
                sleep(dwell)
            }
            app.swipeUp(velocity: .slow)
            sleep(1)
        }
        for _ in 0..<3 { app.swipeDown(velocity: .fast) }
        sleep(1)
    }

    /// A venue friends are at: who's here on its hero, then its chat room, where friends are listed first.
    private func showFriendVenue() {
        let section = app.staticTexts["Where your friends are"]
        let pill = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] ' friend'")).firstMatch
        if section.exists, pill.exists, pill.isHittable {
            pill.tap()
        } else {
            // No friends out: open the first venue so the reviewer still sees the venue screen.
            open(tab: "Venues")
            let row = app.collectionViews.buttons.firstMatch
            guard row.waitForExistence(timeout: 10) else { return }
            row.tap()
        }
        sleep(dwell)
        // Friends here are on the venue's hero, as faces and "4 friends here".
        if app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ' here'")).firstMatch.waitForExistence(timeout: 5) {
            snapshot("Friends Here")
            sleep(dwell)
        }

        let chat = app.descendants(matching: .any)["chat.peek"]
        if scroll(to: chat) {
            chat.tap()
            if app.descendants(matching: .any)["chat.hereNow"].waitForExistence(timeout: 10) {
                snapshot("Chat here now")
            }
            sleep(dwell * 2)
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)
    }

    /// Ping: tells your friends on Hot Mess you want to go out tonight.
    private func showPing() {
        open(tab: "Now")
        let ping = app.buttons["Ping"]
        guard ping.waitForExistence(timeout: 5) else { return }
        ping.tap()
        sleep(dwell * 2)
        snapshot("Ping")
        // Leave without sending.
        app.swipeDown(velocity: .fast)
        sleep(2)
    }

    // MARK: - Helpers

    private func open(tab: String) {
        let button = app.tabBars.buttons[tab]
        if button.waitForExistence(timeout: 5) { button.tap() }
    }

    /// Scrolls the screen up until `element` is on screen.
    @discardableResult
    private func scroll(to element: XCUIElement) -> Bool {
        for _ in 0..<3 {
            if element.exists, element.isHittable { return true }
            app.swipeUp(velocity: .slow)
            sleep(1)
        }
        return element.exists && element.isHittable
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
