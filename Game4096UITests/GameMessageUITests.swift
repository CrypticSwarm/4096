import GameCore
import XCTest

/// The win and game over messages over the board.
final class GameMessageUITests: GameUITestCase {
    /// Swiping left makes a 4096 tile, the winning tile.
    static let almostWon = "2048,2048,0,0;0,0,0,0;0,0,0,0;0,0,0,2"
    /// Swiping left leaves the board full with no merges, whichever tile
    /// spawns in the only free cell.
    static let almostOver = "2,4,2,4;4,2,4,2;2,4,2,8;4,2,8,8"
    /// Swiping left makes 4096 and leaves no move, whatever spawns.
    static let almostWonAndOver = "2048,2048,4,8;8,2,32,16;2,8,2,8;8,2,8,2"

    func launchGame(fixture: String) throws -> GameSession {
        launchGame(LaunchConfiguration(seed: BoardUITests.seed, board: try Board(notation: fixture)))
    }

    /// Swipes down from the top of the screen, outside the board and any
    /// message over it.
    func swipeDownOutsideTheBoard() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 150)))
    }

    /// The win shows once: moves wait until Keep playing, and reaching the
    /// winning tile again, by redo or by a new move, doesn't show it again.
    func testWinShowsOnce() throws {
        var session = try launchGame(fixture: Self.almostWon)
        XCTAssertFalse(winMessage.exists)

        swipe(.left)
        session.move(.left)

        waitForMessage(winMessage)
        XCTAssertTrue(session.shouldPresentWin)
        assertBoard(session.board.notation)
        XCTAssertEqual(scoreBox.value as? String, "4096")
        XCTAssertFalse(undoButton.isEnabled, "Undo waits for the player's choice")
        attachScreenshot(named: "game-win")

        swipeDownOutsideTheBoard()
        settle()
        assertBoard(session.board.notation, "Moves wait until the player chooses")

        tapKeepPlaying()
        session.acknowledgeWin()
        assertShows(session)

        undoButton.tap()
        session.undo()
        assertShows(session)
        redoButton.tap()
        session.redo()
        assertShows(session, "after redoing the winning move")
        assertNoMessage(winMessage, "The win showed again after redo")

        undoButton.tap()
        session.undo()
        play(.left, in: &session)
        XCTAssertEqual(cell(row: 0, column: 0).label, "4096")
        assertNoMessage(winMessage, "The win showed again after a new move")
    }

    /// A move that wins and ends the game shows the win first, then the game
    /// over message.
    func testWinThenGameOver() throws {
        var session = try launchGame(fixture: Self.almostWonAndOver)
        swipe(.left)
        session.move(.left)
        XCTAssertTrue(session.isGameOver)

        tapKeepPlaying()
        session.acknowledgeWin()

        waitForMessage(gameOverMessage)
        assertShows(session)
        XCTAssertTrue(undoButton.isEnabled)
    }

    /// The win message's New Game asks for confirmation too.
    func testNewGameFromTheWinMessage() throws {
        var session = try launchGame(fixture: Self.almostWon)
        swipe(.left)
        session.move(.left)
        waitForMessage(winMessage)

        app.buttons[AccessibilityID.messageNewGame].tap()
        answerNewGameAlert(confirm: true)
        session.restart()

        XCTAssertTrue(winMessage.waitForNonExistence(timeout: 5))
        assertShows(session)
    }

    /// When no move is left the game over message shows, and Undo still
    /// takes the last move back, which removes the message.
    func testGameOverAllowsUndo() throws {
        var session = try launchGame(fixture: Self.almostOver)
        XCTAssertFalse(gameOverMessage.exists)

        swipe(.left)
        session.move(.left)

        XCTAssertTrue(session.isGameOver)
        waitForMessage(gameOverMessage)
        assertShows(session)
        XCTAssertTrue(app.staticTexts["No moves left. You can still undo."].exists)
        XCTAssertTrue(undoButton.isHittable, "The message must not cover Undo")
        attachScreenshot(named: "game-over")

        undoButton.tap()
        session.undo()

        XCTAssertTrue(gameOverMessage.waitForNonExistence(timeout: 5))
        assertShows(session)

        swipe(.left)
        session.move(.left)
        waitForMessage(gameOverMessage)
        app.buttons[AccessibilityID.messageNewGame].tap()
        answerNewGameAlert(confirm: true)
        session.restart()
        XCTAssertTrue(gameOverMessage.waitForNonExistence(timeout: 5))
        assertShows(session)
    }

    /// A game that starts over, with nothing to undo, says so.
    func testGameOverWithNothingToUndo() throws {
        _ = try launchGame(fixture: "2,4,2,4;4,2,4,2;2,4,2,4;4,2,4,2")
        waitForMessage(gameOverMessage)
        XCTAssertTrue(app.staticTexts["No moves left."].exists)
        XCTAssertFalse(undoButton.isEnabled)
    }

    /// Apple's automated accessibility checks with each message showing.
    func testAccessibilityAuditOfMessages() throws {
        _ = try launchGame(fixture: Self.almostWonAndOver)
        swipe(.left)
        waitForMessage(winMessage)
        // The win message is modal: VoiceOver reads only the message, so the
        // rest of the screen, visible around and through it, is text that
        // VoiceOver can't reach, on purpose.
        try performAccessibilityAudit(excluding: .elementDetection)

        app.buttons[AccessibilityID.keepPlaying].tap()
        waitForMessage(gameOverMessage)
        try performAccessibilityAudit()
    }
}
