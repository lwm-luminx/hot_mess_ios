import XCTest

/// Captures the real production UI with the simulator's existing signed-in session.
///
/// HOTMESS_UITEST_BUNDLE_ID drives an installed build instead (social.hotmess.HotMess for production),
/// HOTMESS_UITEST_CITY picks the city the simulator is in (default Seattle), HOTMESS_UITEST_VENUE the venue captured
/// (default the first), HOTMESS_UITEST_PERFORMER the profile captured (default Agony Ray), and HOTMESS_UITEST_SCREENSHOT_DIR also writes each capture there as a PNG.
@MainActor
final class StoreScreenshots: XCTestCase {
    private var app: XCUIApplication!
    private var city: String { Self.value("HOTMESS_UITEST_CITY") ?? "Seattle" }

    override func setUp() async throws {
        continueAfterFailure = false
        app = Self.value("HOTMESS_UITEST_BUNDLE_ID").map { XCUIApplication(bundleIdentifier: $0) } ?? XCUIApplication()
        XCUIApplication(bundleIdentifier: "com.apple.mobilesafari").terminate()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["main.tabs"].waitForExistence(timeout: 30),
                      "Sign in to Hot Mess on this simulator before capturing store screenshots.")
        dismissLocationUpgrade()
        tab("Venues").tap()
        XCTAssertTrue(app.navigationBars[city].waitForExistence(timeout: 30),
                      "Set the screenshot simulator location to \(city) and allow location access.")
    }

    func testNow() {
        open("Now")
        // Now fills in after the location and its events load; an empty Now makes a poor listing.
        requireCard("event")
        snapshot("01-now")
    }
    func testEvents() { open("Events"); requireCard("event"); snapshot("02-events") }
    func testVenues() { open("Venues"); requireCard("venue"); snapshot("03-venues") }
    func testPeople() { everyone(); requireCard("person"); snapshot("04-people") }
    func testEvent() { open("Events"); openCard("event"); snapshot("05-event") }
    func testVenue() {
        open("Venues")
        if let name = Self.value("HOTMESS_UITEST_VENUE") {
            let venue = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
                                                         "card.venue.", name)).firstMatch
            // Swipe the screen, not the first scroll view: that's the map at the top of Venues.
            for _ in 0..<15 {
                if venue.exists && venue.isHittable { break }
                app.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(venue.exists && venue.isHittable, "\(name) must be visible for the venue capture.")
            venue.tap()
            settle()
        } else {
            openCard("venue")
        }
        snapshot("06-venue")
    }
    func testPerson() {
        everyone()
        let name = Self.value("HOTMESS_UITEST_PERFORMER") ?? "Agony Ray"
        let performer = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
                                                         "card.person.", name)).firstMatch
        for _ in 0..<15 {
            if performer.exists && performer.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(performer.exists && performer.isHittable, "\(name) must be visible for the profile capture.")
        performer.tap()
        settle()
        snapshot("07-person")
    }

    private func dismissLocationUpgrade() {
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let keep = system.buttons["Keep Only While Using"]
        if keep.exists { keep.tap() }
    }

    private func everyone() {
        open("People")
        app.buttons["Everyone"].tap()
        settle()
    }

    private func tab(_ name: String) -> XCUIElement {
        let phoneTab = app.tabBars.buttons[name]
        if phoneTab.exists { return phoneTab }
        // iPad floating tabs are exposed as cells/other elements on iOS 27.
        return app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    private func open(_ tab: String) {
        let button = self.tab(tab)
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        settle()
    }

    @discardableResult
    private func requireCard(_ kind: String) -> XCUIElement {
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "card.\(kind).")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "No \(kind) cards loaded; choose a city with listings.")
        return card
    }

    private func openCard(_ kind: String) {
        requireCard(kind).tap()
        settle()
    }

    private func settle() {
        let spinner = app.activityIndicators.firstMatch
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: spinner)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 30), .completed)
        // Give remote photos and the navigation animation time to render.
        sleep(3)
        XCTAssertFalse(app.staticTexts["Something went wrong"].exists,
                       app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " / "))
        dismissLocationUpgrade()
        XCTAssertFalse(app.alerts.firstMatch.exists, "Dismiss permission prompts before capture.")
    }

    private func snapshot(_ name: String) {
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
}
