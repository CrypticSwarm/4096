import GameCore
import XCTest

/// Plays seeded games through the UI next to a `GameSession` playing the
/// same moves, and checks after each action that the screen shows the
/// session: the board (spawned tiles included), the scores, and whether
/// Undo and Redo are enabled.
final class GameScreenUITests: GameUITestCase {
    /// Each swipe of ``directions``, in order, changes this board.
    static let fixture = BoardUITests.fixture
    static let seed = BoardUITests.seed
    static let directions = BoardUITests.expectedMoves.map { $0.direction }

    static func configuration(highScore: Int = 0) throws -> LaunchConfiguration {
        LaunchConfiguration(seed: seed, board: try Board(notation: fixture), highScore: highScore)
    }

    /// The score follows merges; the best score stays until the score beats
    /// it.
    func testScoreAndBestFollowMerges() throws {
        var session = launchGame(try Self.configuration(highScore: 20))
        assertShows(session)

        // The scores are written out rather than only taken from the
        // session, so the test doesn't trust the engine for them.
        for (direction, score, best) in [(Direction.left, 4, 20), (.down, 12, 20), (.right, 32, 32)] {
            play(direction, in: &session)
            XCTAssertEqual(scoreBox.value as? String, String(score), "after \(direction)")
            XCTAssertEqual(bestBox.value as? String, String(best), "after \(direction)")
        }
        attachScreenshot(named: "game-mid")
    }

    /// Undo takes back up to three moves, restoring each board and score seen
    /// before; the best score stays.
    func testUndoRestoresBoardAndScoreForThreeMoves() throws {
        var session = launchGame(try Self.configuration())
        assertShows(session)
        var seen: [(board: String, score: String)] = []
        for direction in Self.directions {
            seen.append((board.value as? String ?? "", scoreBox.value as? String ?? ""))
            play(direction, in: &session)
        }
        let best = bestBox.value as? String

        for count in 1...GameSession.undoLimit {
            undoButton.tap()
            session.undo()
            let expected = seen[seen.count - count]
            assertBoard(expected.board, "after \(count) undos")
            assertValue(of: scoreBox, named: "Score", expected.score, "after \(count) undos")
            assertShows(session, "after \(count) undos")
            XCTAssertEqual(bestBox.value as? String, best)
            if count == 1 {
                attachScreenshot(named: "game-after-undo")
            }
        }
        XCTAssertFalse(session.canUndo, "Only three moves can be undone")
    }

    /// Redo plays each undone move again with the same new tile.
    func testRedoReplaysTheSameMoves() throws {
        var session = launchGame(try Self.configuration())
        var played: [GameSession] = []
        for direction in Self.directions.prefix(3) {
            play(direction, in: &session)
            played.append(session)
        }

        for _ in 0..<3 {
            undoButton.tap()
            session.undo()
        }
        assertShows(session)
        for index in 0..<3 {
            redoButton.tap()
            session.redo()
            XCTAssertEqual(session.board, played[index].board)
            XCTAssertEqual(session.score, played[index].score)
            assertShows(session, "after redo \(index + 1)")
        }
    }

    /// A swipe after undo draws a new tile, and the undone move can't be
    /// redone.
    func testSwipeAfterUndoDropsRedo() throws {
        var session = launchGame(try Self.configuration())
        play(.left, in: &session)
        play(.down, in: &session)
        undoButton.tap()
        session.undo()
        assertShows(session)
        XCTAssertTrue(redoButton.isEnabled)

        play(.right, in: &session)

        XCTAssertFalse(redoButton.isEnabled)
    }

    /// New Game asks first. Cancelling keeps the game and its history;
    /// confirming starts over with the best score kept and nothing to undo.
    func testNewGameAsksForConfirmation() throws {
        var session = launchGame(try Self.configuration())
        play(.left, in: &session)
        play(.down, in: &session)
        undoButton.tap()
        session.undo()

        newGameButton.tap()
        XCTAssertTrue(newGameAlert.waitForExistence(timeout: 5))
        attachScreenshot(named: "game-new-game-confirmation")
        answerNewGameAlert(confirm: false)
        assertShows(session, "after cancelling")

        tapNewGame(confirm: true)
        session.restart()
        XCTAssertEqual(session.score, 0)
        XCTAssertEqual(session.highScore, 12)
        assertShows(session, "after a new game")
    }

    /// Large numbers in the scores and on the tiles, long after the win.
    func testLargeNumbers() throws {
        let board = try Board(notation: "2,8,32,4;16,128,1024,8;4,512,8192,16384;0,4,65536,131072")
        var session = launchGame(
            LaunchConfiguration(seed: Self.seed, board: board, score: 2_345_678, highScore: 12_345_678))
        // A board with a winning tile starts as just won.
        tapKeepPlaying()
        session.acknowledgeWin()
        assertShows(session)
        XCTAssertFalse(gameOverMessage.exists)
        attachScreenshot(named: "game-large-numbers")
    }
}
