import GameCore
import Testing

/// Scenarios for undo and redo, mostly comparing a session with the states of
/// a game played from a fixed seed (see ``playedGame(moves:seed:)``).
struct UndoRedoTests {
    @Test func newGameHasNothingToUndoOrRedo() {
        var session = GameSession(rules: .classic, seed: 1)
        let before = session
        #expect(!session.canUndo && !session.canRedo)
        #expect(session.undoCount == 0 && session.redoCount == 0)
        #expect(session.undo() == false)
        #expect(session.redo() == nil)
        #expect(session == before)
    }

    @Test func undoRestoresBoardAndScore() throws {
        let board = try Board(rows: [[2, 2, 4, 4], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        var session = GameSession(rules: .classic, board: board, score: 10, seed: 5)
        session.move(.left)
        #expect(session.score == 22)

        #expect(session.undo() == true)

        #expect(session.board == board)
        #expect(session.score == 10)
        #expect(session.highScore == 22)
    }

    @Test func undoStopsAfterTheLimit() {
        let states = playedGame(moves: 5).states
        var session = states[5]
        #expect(session.undoCount == GameSession.undoLimit)
        for back in 1...3 {
            #expect(session.undo() == true)
            #expect(session.board == states[5 - back].board)
            #expect(session.score == states[5 - back].score)
            #expect(session.undoCount == 3 - back)
            #expect(session.redoCount == back)
        }
        let atLimit = session
        #expect(!session.canUndo)
        #expect(session.undo() == false)
        #expect(session == atLimit)
    }

    @Test func fewerMovesThanTheLimitAllUndo() {
        let states = playedGame(moves: 2).states
        var session = states[2]
        #expect(session.undoCount == 2)
        session.undo()
        session.undo()
        #expect(session.board == states[0].board)
        #expect(session.score == 0)
        #expect(!session.canUndo)
    }

    @Test func windowRollsWithEachMove() {
        let states = playedGame(moves: 8).states
        for count in 3...8 {
            var session = states[count]
            #expect(session.undoCount == 3)
            for _ in 0..<3 { session.undo() }
            #expect(session.board == states[count - 3].board)
            #expect(!session.canUndo)
        }
    }

    /// Undo is usable again after moving on: undo 3, redo 3, move 3, undo 3.
    @Test func undoWorksRepeatedly() {
        let game = playedGame(moves: 6)
        var session = game.states[3]
        for _ in 0..<3 { session.undo() }
        for _ in 0..<3 { session.redo() }
        #expect(session == game.states[3])
        for index in 3..<6 {
            // The generator is back where it was, so the same swipes draw the
            // same tiles.
            #expect(session.move(game.moves[index].direction) == game.moves[index])
        }
        #expect(session == game.states[6])
        for back in 1...3 {
            session.undo()
            #expect(session.board == game.states[6 - back].board)
        }
    }

    @Test func redoReplaysTheSameMovesInOrder() {
        let game = playedGame(moves: 5)
        var session = game.states[5]
        for _ in 0..<3 { session.undo() }

        for index in 2..<5 {
            #expect(session.redo() == game.moves[index], "same direction and spawn")
            #expect(session.board == game.states[index + 1].board)
            #expect(session.score == game.states[index + 1].score)
        }

        #expect(session == game.states[5], "redo draws nothing from the generator")
        #expect(!session.canRedo)
        #expect(session.redo() == nil)
    }

    @Test func redoAfterPartialUndo() {
        let states = playedGame(moves: 5).states
        var session = states[5]
        session.undo()
        session.undo()
        #expect(session.redo() != nil)
        #expect(session.board == states[4].board)
        #expect(session.undoCount == 2)
        #expect(session.redoCount == 1)
        session.undo()
        session.undo()
        #expect(session.board == states[2].board)
        #expect(session.redoCount == 3)
        session.redo()
        session.redo()
        session.redo()
        #expect(session == states[5])
    }

    @Test func undoThenRedoIsIdentity() {
        let states = playedGame(moves: 6).states
        for index in 1...6 {
            var session = states[index]
            session.undo()
            session.redo()
            #expect(session == states[index])
        }
    }

    @Test func swipeAfterUndoDrawsANewTileAndForgetsRedo() throws {
        let game = playedGame(moves: 5)
        var session = game.states[5]
        session.undo()
        session.undo()
        session.undo()

        let played = session.move(game.moves[2].direction)
        let move = try #require(played)

        // The generator moved on, so the tile is drawn afresh; in this game it
        // lands elsewhere than the undone move's.
        #expect(move.spawn != game.moves[2].spawn)
        #expect(!session.canRedo)
        #expect(session.redo() == nil)
        #expect(session.undoCount == 1)
        session.undo()
        #expect(session.board == game.states[2].board)
        #expect(!session.canUndo, "the moves before the undone ones fell out of the window")
        #expect(session.redoCount == 1)
        #expect(session.redo() == move, "only the new move can be redone")
        #expect(!session.canRedo)
    }

    @Test func swipeAfterPartialUndoKeepsTheRemainingHistory() {
        let game = playedGame(moves: 5)
        var session = game.states[5]
        session.undo()
        session.undo()
        #expect(session.move(game.moves[3].direction) != nil)
        #expect(session.undoCount == 2)
        #expect(session.redoCount == 0)
        session.undo()
        session.undo()
        #expect(session.board == game.states[2].board)
        #expect(!session.canUndo)
    }

    @Test func swipeThatChangesNothingKeepsRedo() throws {
        let board = try Board(rows: [[2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        var session = GameSession(rules: .classic, board: board, seed: 3)
        let played = session.move(.right)
        session.undo()
        let afterUndo = session

        // Back on a board with one tile in the top-left corner, left and up
        // change nothing.
        #expect(session.move(.left) == nil)
        #expect(session.move(.up) == nil)

        #expect(session == afterUndo)
        #expect(session.redo() == played)
    }

    @Test func undoAndRedoWorkFromGameOver() throws {
        var session = GameSession(
            rules: GameSessionTests.foursOnly, board: try Board(rows: GameSessionTests.oneMoveLeft), seed: 1)
        session.move(.left)
        let over = session
        #expect(session.isGameOver)

        #expect(session.undo() == true)
        #expect(!session.isGameOver)
        #expect(session.board.rows == GameSessionTests.oneMoveLeft)
        #expect(session.redo() != nil)
        #expect(session == over)
    }

    @Test func restartClearsUndoAndRedo() {
        var session = playedGame(moves: 5).states[5]
        session.undo()
        #expect(session.canUndo && session.canRedo)
        session.restart()
        #expect(!session.canUndo && !session.canRedo)
        #expect(session.undo() == false)
        #expect(session.redo() == nil)
    }

    @Test func undoNeverLowersTheHighScore() {
        let states = playedGame(moves: 40).states
        var session = states[40]
        let highScore = session.highScore
        #expect(highScore > states[37].score)
        for _ in 0..<3 { session.undo() }
        #expect(session.score == states[37].score)
        #expect(session.highScore == highScore)
    }
}
