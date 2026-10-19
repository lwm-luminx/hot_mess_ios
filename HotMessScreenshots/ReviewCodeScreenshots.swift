//
//  ReviewCodeScreenshots.swift
//  HotMessScreenshots
//

import XCTest

/// The App Store review screenshots, signed in with App Review codes rather than anyone's own account: the main
/// reviewer's walk through chat, reporting, Ping, Now, a venue tonight, karaoke, a host's events and Blocked People,
/// and the reviewer a venue banned, who no longer sees that venue.
///
/// Setup, before a run: turn App Review on for the audience (and AudienceKit Demo for the main code), then Reset App
/// Review (or add the codes on the console's App Review card), naming the venue the banned reviewer is banned from.
/// The codes come from the environment, never the repository:
///
///   HOTMESS_UITEST_REVIEW_CODE         the main reviewer's code (testReviewerScreens); the .env's APP_REVIEW_CODE
///   HOTMESS_UITEST_BANNED_REVIEW_CODE  the banned reviewer's code (testBannedReviewerScreens); APP_REVIEW_BANNED_CODE
///   HOTMESS_UITEST_VENUE               the busy venue to pretend to be at, default "Club Try-Angles"
///   HOTMESS_UITEST_BANNED_VENUE        the venue the banned reviewer is banned from, default HOTMESS_UITEST_VENUE
///   HOTMESS_UITEST_HOST                a host whose page lists upcoming events, default "Drew G"
///   HOTMESS_UITEST_SCREENSHOT_DIR      also write each capture there as a PNG (the simulator shares the Mac's disk)
///
/// Scripts/review-screenshots.sh passes the root .env to the runner; otherwise pass them as `TEST_RUNNER_<name>=…` on the
/// xcodebuild command line. Run with the Screenshots scheme
/// (the next API) or, for production data, against an installed Release build by also setting
/// HOTMESS_UITEST_BUNDLE_ID=social.hotmess.HotMess (the review aids still show for review accounts). Nothing here sends
/// a report, a block, a Ping or a karaoke signup: each sheet is captured and cancelled.
@MainActor
final class ReviewCodeScreenshots: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        if let bundleID = Self.value("HOTMESS_UITEST_BUNDLE_ID") {
            app = XCUIApplication(bundleIdentifier: bundleID)
        } else {
            app = XCUIApplication()
        }
        // Signed out each run, where the build has the test hooks (Debug and Staging); a Release build signs out below.
        app.launchArguments = ["-HotMessUITestSignedOut", "-HotMessUseNextAPI"]
        addUIInterruptionMonitor(withDescription: "Location and notification prompts") { alert in
            for label in ["Keep Only While Using", "Allow While Using App", "Allow Once", "Don’t Allow", "Don't Allow"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); return true }
            }
            return false
        }
    }

    // MARK: - The main reviewer

    func testReviewerScreens() throws {
        let code = try Self.required("HOTMESS_UITEST_REVIEW_CODE", or: "APP_REVIEW_CODE")
        let venue = Self.value("HOTMESS_UITEST_VENUE") ?? "Club Try-Angles"
        try signIn(code: code, captureLogin: true)

        // A busy venue tonight: lineup, karaoke and Ping here, then pretend to be there to open its chat.
        openVenue(named: venue)
        capture("06-venue-tonight")
        pretendToBeHere()
        let peek = app.descendants(matching: .any)["chat.peek"]
        if scroll(to: peek) { capture("06b-venue-chat-peek") }

        openChat()
        capture("01-chat")
        showReportSheet()
        back()

        // Karaoke and Ping open sheets that are captured and cancelled.
        scrollToTop()
        if tapIfPresent(app.buttons["Sign up to sing"]) {
            capture("07-karaoke-signup")
            cancelSheet()
        }
        if tapIfPresent(app.buttons["Ping here"]) {
            capture("04-ping-composer")
            cancelSheet()
        }

        open(tab: "Now")
        capture("05-now")

        openHost(named: Self.value("HOTMESS_UITEST_HOST") ?? "Drew G")
        capture("13-host-events")

        open(tab: "Me")
        let blocked = app.buttons["me.blocked"]
        XCTAssertTrue(scroll(to: blocked), "Me › Blocked People didn't appear")
        blocked.tap()
        settle()
        capture("11-blocked-people")
    }

    // MARK: - The reviewer a venue banned

    /// The banned reviewer's view: the venue is gone from Venues and its events are gone from Events.
    func testBannedReviewerScreens() throws {
        let code = try Self.required("HOTMESS_UITEST_BANNED_REVIEW_CODE", or: "APP_REVIEW_BANNED_CODE")
        let venue = Self.value("HOTMESS_UITEST_BANNED_VENUE") ?? Self.value("HOTMESS_UITEST_VENUE") ?? "Club Try-Angles"
        try signIn(code: code, captureLogin: false)

        open(tab: "Venues")
        capture("20-banned-venues")
        XCTAssertFalse(card(kind: "venue", containing: venue).exists, "\(venue) still shows for the banned reviewer")
        for _ in 0..<6 { app.swipeUp() }
        settle()
        capture("21-banned-venues-scrolled")
        XCTAssertFalse(card(kind: "venue", containing: venue).exists, "\(venue) still shows for the banned reviewer")

        open(tab: "Events")
        capture("22-banned-events")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "at \(venue)")).firstMatch.exists,
                       "\(venue)'s events still show for the banned reviewer")

        open(tab: "Now")
        capture("23-banned-now")
    }

    // MARK: - Sign-in

    private func signIn(code: String, captureLogin: Bool) throws {
        XCUIDevice.shared.location = XCUILocation(location: StoreScreenshots.location)
        app.launch()
        let tabs = app.descendants(matching: .any)["main.tabs"]
        let reviewCode = app.buttons["login.reviewCode"]
        if tabs.waitForExistence(timeout: 10) {
            // A Release build keeps its session: sign out, so the code decides who is signed in.
            signOut()
        }
        // Signing out (or a link) can bounce through Safari, which leaves "◂ Safari" in the status bar of every capture.
        XCUIApplication(bundleIdentifier: "com.apple.mobilesafari").terminate()
        app.terminate()
        XCUIDevice.shared.location = XCUILocation(location: StoreScreenshots.location)
        app.launch()
        XCTAssertTrue(reviewCode.waitForExistence(timeout: 20), "The sign-in screen didn't appear")
        if captureLogin { capture("08-login-eula") }

        let eula = app.buttons["login.eulaCheckbox"], age = app.buttons["login.ageCheckbox"]
        if eula.exists && eula.value as? String != "1" { eula.tap() }
        if age.exists && age.value as? String != "1" { age.tap() }
        if captureLogin {
            capture("08b-login-eula-checked")
            let terms = app.buttons["login.openEULA"]
            if tapIfPresent(terms) {
                sleep(2)
                capture("09-eula")
                app.scrollViews.firstMatch.swipeUp(velocity: .slow)
                sleep(2)
                capture("09b-eula-24h")
                let close = app.buttons["eula.close"]
                if !tapIfPresent(close) { _ = tapIfPresent(app.buttons["Close"]) }
            }
        }

        reviewCode.tap()
        let field = app.textFields["reviewCode.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The App Review code sheet didn't open")
        field.tap()
        field.typeText(code)
        app.buttons["reviewCode.submit"].tap()
        XCTAssertTrue(tabs.waitForExistence(timeout: 30), "The App Review code didn't sign in; check it on the console's App Review card")
        app.tap() // lets the interruption monitor answer a location or notification prompt
        settle()
    }

    private func signOut() {
        open(tab: "Me")
        let signOut = app.buttons["Sign Out"]
        guard scroll(to: signOut) else { return XCTFail("Me › Sign Out didn't appear") }
        signOut.tap()
        let confirm = app.alerts.buttons["Sign Out"].exists ? app.alerts.buttons["Sign Out"] : app.sheets.buttons["Sign Out"]
        _ = tapIfPresent(confirm)
    }

    // MARK: - Steps

    private func openVenue(named name: String) {
        open(tab: "Venues")
        let venue = card(kind: "venue", containing: name)
        XCTAssertTrue(scroll(to: venue), "\(name) isn't in Venues; set HOTMESS_UITEST_VENUE or the simulator's location")
        venue.tap()
        settle()
    }

    private func pretendToBeHere() {
        let pretend = app.buttons["Pretend I'm here"]
        if scroll(to: pretend) {
            pretend.tap()
            settle()
        } else {
            XCTAssertTrue(app.buttons["Stop pretending"].exists, "Pretend I'm here didn't show: is this a review account?")
        }
    }

    private func openChat() {
        // The whole peek opens the room; its "Join the chat" line isn't a button of its own.
        let peek = app.descendants(matching: .any)["chat.peek"]
        XCTAssertTrue(scroll(to: peek), "The venue's chat peek didn't show")
        peek.tap()
        let accept = app.buttons["chat.acceptTerms"]
        if accept.waitForExistence(timeout: 5) {
            capture("10-chat-rules")
            accept.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["chat.hereNow"].waitForExistence(timeout: 15), "The chat didn't open")
        settle()
    }

    /// Long-presses someone else's message until its Report… menu shows, captures the menu and the report sheet, and
    /// cancels: nothing is reported.
    private func showReportSheet() {
        let report = app.buttons["Report…"]
        // A message reads "Name: text", a role's (the venue's own posts too) "Name, Role: text"; your own start with
        // "You". A person's message comes first, for the Block line in the menu.
        let all = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES %@ AND NOT label BEGINSWITH %@", "^[^:]{1,60}: .+", "You"))
            .allElementsBoundByIndex.reversed()
        let messages = all.filter { !$0.label.contains(", ") } + all.filter { $0.label.contains(", ") }
        for message in messages.prefix(12) where message.isHittable {
            message.press(forDuration: 1.2)
            if report.waitForExistence(timeout: 2) { break }
            app.tap()
        }
        guard report.exists else { return XCTFail("No message offered Report…") }
        capture("02-chat-report-menu")
        report.tap()
        XCTAssertTrue(app.navigationBars["Report"].waitForExistence(timeout: 5), "The report sheet didn't open")
        capture("03-report-sheet")
        cancelSheet()
    }

    private func openHost(named name: String) {
        open(tab: "People")
        _ = tapIfPresent(app.buttons["Everyone"])
        settle()
        let host = card(kind: "person", containing: name)
        XCTAssertTrue(scroll(to: host), "\(name) isn't in People › Everyone; set HOTMESS_UITEST_HOST")
        host.tap()
        settle()
    }

    // MARK: - Helpers

    private func card(kind: String, containing label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "card.\(kind).", label)).firstMatch
    }

    private func tab(_ name: String) -> XCUIElement {
        let phoneTab = app.tabBars.buttons[name]
        if phoneTab.exists { return phoneTab }
        return app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    private func open(tab name: String) {
        let button = tab(name)
        XCTAssertTrue(button.waitForExistence(timeout: 10), "The \(name) tab didn't appear")
        button.tap()
        settle()
    }

    private func back() {
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
        settle()
    }

    private func cancelSheet() {
        _ = tapIfPresent(app.buttons["Cancel"])
        settle()
    }

    private func scrollToTop() {
        for _ in 0..<4 { app.swipeDown() }
    }

    @discardableResult
    private func tapIfPresent(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 3) else { return false }
        if !element.isHittable { _ = scroll(to: element) }
        element.tap()
        settle()
        return true
    }

    /// Scrolls down until `element` can be tapped, then back up a little if it's under the floating tab bar.
    private func scroll(to element: XCUIElement) -> Bool {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return true }
            app.swipeUp(velocity: .slow)
        }
        return element.exists && element.isHittable
    }

    private func settle() {
        let spinner = app.activityIndicators.firstMatch
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: spinner)
        _ = XCTWaiter.wait(for: [finished], timeout: 20)
        // Remote photos and the navigation animation.
        sleep(2)
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = Self.value("HOTMESS_UITEST_SCREENSHOT_DIR") {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: url)
        }
    }

    private static func value(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `key`, else the root .env's name for it (Scripts/review-screenshots.sh passes the .env through).
    private static func required(_ key: String, or envFileKey: String) throws -> String {
        guard let value = value(key) ?? value(envFileKey) else {
            throw XCTSkip("Set \(envFileKey) in the root .env, or TEST_RUNNER_\(key)=… on the xcodebuild command line, to run this.")
        }
        return value
    }
}
