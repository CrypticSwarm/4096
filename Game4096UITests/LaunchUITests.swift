import XCTest

@MainActor
final class LaunchUITests: XCTestCase {
    func testLaunchShowsTitle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts[AccessibilityID.title].waitForExistence(timeout: 10))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Launch"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
