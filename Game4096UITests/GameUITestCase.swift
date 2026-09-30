import GameCore
import XCTest

/// Launches the app with a `LaunchConfiguration` and provides helpers to read
/// the board, attach screenshots and keep system UI out of the way.
@MainActor
class GameUITestCase: XCTestCase {
    private(set) var app: XCUIApplication!

    /// The board container; its value is the board in notation.
    var board: XCUIElement {
        app.descendants(matching: .any).matching(identifier: AccessibilityID.board).firstMatch
    }

    /// The cell at `row` and `column`; its label is the tile's value or "Empty".
    func cell(row: Int, column: Int) -> XCUIElement {
        board.descendants(matching: .any).matching(identifier: AccessibilityID.cell(row: row, column: column))
            .firstMatch
    }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // System alerts (such as a permission prompt) block taps and swipes;
        // dismiss any that show up while the tests interact with the app.
        // Only known system buttons, so an alert of the app's own isn't
        // dismissed behind a test's back.
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            for label in ["OK", "Not Now", "Continue", "Dismiss", "Close"] where alert.buttons[label].exists {
                XCTContext.runActivity(named: "Dismiss system alert \"\(alert.label)\" with \(label)") { _ in
                    alert.buttons[label].tap()
                }
                return true
            }
            return false
        }
    }

    /// Launches the app with `configuration` and waits for the board.
    func launch(_ configuration: LaunchConfiguration) {
        app.launchArguments = configuration.arguments
        app.launch()
        XCTAssertTrue(board.waitForExistence(timeout: 10), "The board didn't appear")
        dismissSystemNotifications()
    }

    /// Swipes the board in `direction`.
    func swipe(_ direction: Direction) {
        switch direction {
        case .up: board.swipeUp()
        case .down: board.swipeDown()
        case .left: board.swipeLeft()
        case .right: board.swipeRight()
        }
    }

    /// Waits until the board's accessibility value is `expected`, in board
    /// notation, and fails with the actual board otherwise.
    func assertBoard(
        _ expected: String, timeout: TimeInterval = 10, _ message: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        // Polls with fresh reads; an NSPredicate expectation on the element
        // proved flaky right after launch.
        let deadline = Date().addingTimeInterval(timeout)
        var actual = board.value as? String
        while actual != expected && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            actual = board.value as? String
        }
        if actual != expected {
            XCTFail("Board is \(actual ?? "nil"), expected \(expected). \(message)", file: file, line: line)
        }
    }

    /// Attaches a screenshot of the app, kept even when the test passes. Waits
    /// for animations to finish first.
    func attachScreenshot(named name: String) {
        settle()
        dismissSystemNotifications()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Waits long enough for a move's animation to end: a 100 ms slide, then
    /// a 200 ms spring that takes about 0.35 s to come to rest.
    func settle() {
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "Animations settle")], timeout: 0.8)
    }

    /// Swipes away notification banners that the simulator shows over the
    /// app (for example about Apple Intelligence on a fresh simulator), so
    /// they neither catch swipes nor appear in screenshots.
    func dismissSystemNotifications() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let banner = springboard.otherElements["NotificationShortLookView"]
            guard banner.exists else { return }
            banner.swipeUp()
            _ = banner.waitForNonExistence(timeout: 2)
        }
    }
}
