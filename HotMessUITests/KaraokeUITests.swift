import XCTest

@MainActor
final class KaraokeUITests: XCTestCase {
    override func tearDown() {
        let attachment = XCTAttachment(screenshot: XCUIApplication().screenshot())
        attachment.lifetime = .keepAlways; add(attachment)
        super.tearDown()
    }
    private func open(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-HotMessUITestKaraoke=\(mode)"]
        app.launch()
        return app
    }
    func testVenueControlledSessionDisplaysAndOpens() {
        let app = open("venue")
        XCTAssertTrue(app.descendants(matching: .any)["karaoke.badge"].waitForExistence(timeout: 10))
        let link = app.descendants(matching: .any)["karaoke.join"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(app.staticTexts["karaoke.opened"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["karaoke.opened"].label, "https://www.karafun.com/123456/")
    }
    func testOwnSessionOpensItsOverride() {
        let app = open("own")
        let link = app.descendants(matching: .any)["karaoke.join"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        XCTAssertTrue(app.staticTexts["karaoke.opened"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["karaoke.opened"].label, "https://www.karafun.com/654321/")
    }
    func testDisconnectedKaraokeHasBadgeAndInstructionsButNoBrokenLink() {
        let app = open("disconnected")
        XCTAssertTrue(app.descendants(matching: .any)["karaoke.badge"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Ask the host how to join the karaoke session."].exists)
        XCTAssertFalse(app.descendants(matching: .any)["karaoke.join"].exists)
    }
    func testAudienceKitKaraokePointsToTheVenueToSignUp() {
        let app = open("audiencekit")
        XCTAssertTrue(app.descendants(matching: .any)["karaoke.badge"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["karaoke.signUpPointer"].exists)
        XCTAssertFalse(app.staticTexts["Ask the host how to join the karaoke session."].exists)
        XCTAssertFalse(app.descendants(matching: .any)["karaoke.join"].exists)
    }
    func testOrdinaryEventHasNoKaraokeBadgeOrSession() {
        let app = open("none")
        XCTAssertTrue(app.navigationBars["Karaoke test"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["karaoke.badge"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["karaoke.join"].exists)
    }
}
