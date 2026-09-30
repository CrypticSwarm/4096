import GameCore
import XCTest

/// The game in progress survives the app being terminated, since every
/// change is saved as it happens.
final class PersistenceUITests: GameUITestCase {
    func testGameContinuesAfterRelaunch() throws {
        // A folder of its own, so the test neither sees nor changes other
        // saved games.
        let storage = LaunchConfiguration.Storage.folder("UITest-\(UUID().uuidString)")
        let configuration = try GameScreenUITests.configuration()
        var session = launchGame(
            LaunchConfiguration(seed: configuration.seed, board: configuration.board, storage: storage))
        for direction in GameScreenUITests.directions.prefix(3) {
            play(direction, in: &session)
        }
        undoButton.tap()
        session.undo()
        assertShows(session, "before terminating")

        // Terminating skips the save when the app moves to the background,
        // so the game must already be saved.
        app.terminate()
        // Without -board the app continues the saved game; the seed would
        // only be used for a new game.
        launch(LaunchConfiguration(seed: 1, storage: storage))

        assertShows(session, "after relaunching")
        // The history came back: redo replays the same tile, and undo goes
        // back to the start.
        redoButton.tap()
        session.redo()
        assertShows(session, "after redo")
        for _ in 0..<3 {
            undoButton.tap()
            session.undo()
        }
        XCTAssertEqual(session.board, configuration.board)
        assertShows(session, "after undoing every move")
        // So did the random number generator: a new move draws the same
        // tile as it would have without the relaunch.
        play(.left, in: &session)
    }
}
