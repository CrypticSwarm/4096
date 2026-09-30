import GameCore
import XCTest

/// Launches the app with a `LaunchConfiguration` and provides helpers to read
/// the board and scores, compare them with a `GameSession` played alongside,
/// attach screenshots and keep system UI out of the way.
@MainActor
class GameUITestCase: XCTestCase {
    private(set) var app: XCUIApplication!

    /// The board container; its value is the board in notation.
    var board: XCUIElement { element(AccessibilityID.board) }

    /// The score box; its value is the score.
    var scoreBox: XCUIElement { element(AccessibilityID.score) }
    /// The best score box; its value is the high score.
    var bestBox: XCUIElement { element(AccessibilityID.best) }
    var undoButton: XCUIElement { app.buttons[AccessibilityID.undo] }
    var redoButton: XCUIElement { app.buttons[AccessibilityID.redo] }
    var newGameButton: XCUIElement { app.buttons[AccessibilityID.newGame] }
    /// The alert asking to confirm a new game.
    var newGameAlert: XCUIElement { app.alerts[AccessibilityID.newGameAlertTitle] }
    var winMessage: XCUIElement { element(AccessibilityID.winMessage) }
    var gameOverMessage: XCUIElement { element(AccessibilityID.gameOverMessage) }

    /// The element of any type with `identifier`.
    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
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

    /// Launches the app with `configuration`, followed by `extraArguments`
    /// (such as system settings), and waits for the board.
    ///
    /// UI tests never touch the player's saved game: the standard storage
    /// is replaced with memory storage, so every launch starts afresh unless
    /// a test names a storage folder of its own.
    func launch(_ configuration: LaunchConfiguration, extraArguments: [String] = []) {
        var configuration = configuration
        if configuration.storage == .standard {
            configuration.storage = .memory
        }
        app.launchArguments = configuration.arguments + extraArguments
        app.launch()
        XCTAssertTrue(board.waitForExistence(timeout: 10), "The board didn't appear")
        dismissSystemNotifications()
    }

    /// Launches `configuration` (which must use memory storage, the
    /// default, or a folder no other test uses) and returns the session the
    /// app starts with: its board, or a new game from its seed.
    func launchGame(_ configuration: LaunchConfiguration) -> GameSession {
        precondition(configuration.seed != nil, "The session is only known with a seed")
        launch(configuration)
        return configuration.newSession(randomSeed: 0)
    }

    /// Swipes in `direction` in the app and in `session`, and checks that
    /// the screen shows the result.
    func play(
        _ direction: Direction, in session: inout GameSession, file: StaticString = #filePath, line: UInt = #line
    ) {
        let move = session.move(direction)
        XCTAssertNotNil(move, "\(direction) doesn't change the board", file: file, line: line)
        swipe(direction)
        assertShows(session, "after swiping \(direction)", file: file, line: line)
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
        assertValue(of: board, named: "Board", expected, timeout: timeout, message, file: file, line: line)
    }

    /// Waits until `element`'s accessibility value is `expected`, and fails
    /// with the actual value otherwise.
    func assertValue(
        of element: XCUIElement, named name: String, _ expected: String, timeout: TimeInterval = 10,
        _ message: String = "", file: StaticString = #filePath, line: UInt = #line
    ) {
        // Polls with fresh reads; an NSPredicate expectation on the element
        // proved flaky right after launch.
        let deadline = Date().addingTimeInterval(timeout)
        var actual = element.value as? String
        while actual != expected && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            actual = element.value as? String
        }
        if actual != expected {
            XCTFail("\(name) is \(actual ?? "nil"), expected \(expected). \(message)", file: file, line: line)
        }
    }

    /// Checks that the screen shows `session`: its board, score and high
    /// score, and Undo and Redo enabled exactly when it can undo and redo.
    func assertShows(
        _ session: GameSession, _ message: String = "", file: StaticString = #filePath, line: UInt = #line
    ) {
        assertBoard(session.board.notation, message, file: file, line: line)
        assertValue(of: scoreBox, named: "Score", String(session.score), message, file: file, line: line)
        assertValue(of: bestBox, named: "Best", String(session.highScore), message, file: file, line: line)
        XCTAssertEqual(undoButton.isEnabled, session.canUndo, "Undo enabled. \(message)", file: file, line: line)
        XCTAssertEqual(redoButton.isEnabled, session.canRedo, "Redo enabled. \(message)", file: file, line: line)
    }

    /// Taps New Game and answers the confirmation: confirms a new game, or
    /// cancels it.
    func tapNewGame(confirm: Bool, file: StaticString = #filePath, line: UInt = #line) {
        newGameButton.tap()
        answerNewGameAlert(confirm: confirm, file: file, line: line)
    }

    /// Waits until `message` (``winMessage`` or ``gameOverMessage``) exists
    /// and has faded in.
    func waitForMessage(_ message: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(message.waitForExistence(timeout: 5), "No \(message.identifier)", file: file, line: line)
        // It exists as soon as it is inserted, then waits for the tiles to
        // settle and fades in: 1 s in all.
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "Message fades in")], timeout: 1.2)
    }

    /// Checks that `message` doesn't appear, giving it time to fade in.
    func assertNoMessage(
        _ message: XCUIElement, _ description: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(message.waitForExistence(timeout: 1.5), description, file: file, line: line)
    }

    /// Waits for the win message and dismisses it with Keep playing.
    func tapKeepPlaying(file: StaticString = #filePath, line: UInt = #line) {
        waitForMessage(winMessage, file: file, line: line)
        app.buttons[AccessibilityID.keepPlaying].tap()
        XCTAssertTrue(winMessage.waitForNonExistence(timeout: 5), "The win message stayed", file: file, line: line)
    }

    /// Answers the alert asking to confirm a new game.
    func answerNewGameAlert(confirm: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(newGameAlert.waitForExistence(timeout: 5), "No confirmation asked", file: file, line: line)
        newGameAlert.buttons[confirm ? "New Game" : "Cancel"].tap()
        XCTAssertTrue(newGameAlert.waitForNonExistence(timeout: 5), "The alert stayed", file: file, line: line)
    }

    /// Apple's automated accessibility checks. Contrast and Dynamic Type are
    /// deliberate exceptions: the classic colors of the tiles and of the
    /// score boxes are kept (Increase Contrast fixes them), tile numbers
    /// scale with the tile, and game chrome stops growing at
    /// `Theme.largestChromeTextSize` (showing the Large Content Viewer
    /// instead). Other exceptions are passed in `excluding`.
    ///
    /// The audit runs to the end, collecting every issue, and then fails once
    /// listing them all (and prints each on its own line of the log), so one
    /// run shows every problem.
    func performAccessibilityAudit(
        excluding exceptions: XCUIAccessibilityAuditType = [], file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let types = XCUIAccessibilityAuditType.all.subtracting([.contrast, .dynamicType]).subtracting(exceptions)
        var issues: [String] = []
        try app.performAccessibilityAudit(for: types) { issue in
            let element = issue.element.map {
                "element of type \($0.elementType.rawValue) \"\($0.identifier)\" labeled \"\($0.label)\""
            }
            issues.append(
                "\(issue.compactDescription) (type \(issue.auditType.rawValue)): \(issue.detailedDescription)"
                    + " on \(element ?? "no element")")
            // Handled, so the audit goes on to the next issue.
            return true
        }
        guard !issues.isEmpty else { return }
        let numbered = issues.enumerated().map { "(\($0.offset + 1)) \($0.element)" }
        for issue in numbered {
            print("Accessibility issue \(issue)")
        }
        // One line, so the whole list reaches CI's failure annotation.
        XCTFail("\(issues.count) accessibility issues: " + numbered.joined(separator: " "), file: file, line: line)
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
