import GameCore
import Testing

/// Scenarios for undo and redo. Each plays a classic game from a fixed seed
/// and compares the session with copies saved along the way: sessions are
/// values, so a copy is a snapshot of the whole state, generator included.
struct UndoRedoTests {
    /// A new game and the sessions after each of `count` moves, so that
    /// `states[n]` is the session after `n` moves.
    static func play(_ count: Int, seed: UInt64 = 99) -> [GameSession] {
        var session = GameSession(rules: .classic, seed: seed)
        var states = [session]
        var index = 0
        while states.count <= count {
            if session.move(Direction.allCases[index % 4]) != nil {
                states.append(session)
            }
            index += 1
        }
        return states
    }

    @Test func newGameHasNothingToUndoOrRedo() {
        var session = GameSession(rules: .classic, seed: 1)
        let before = session
        #expect(!session.canUndo && !session.canRedo)
        #expect(session.undoCount == 0 && session.redoCount == 0)
        #expect(session.undo() == nil)
        #expect(session.redo() == nil)
        #expect(session == before)
    }

    @Test func undoRestoresBoardAndScoreAndReturnsTheMove() throws {
        let board = try Board(rows: [[2, 2, 4, 4], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        var session = GameSession(rules: .classic, board: board, score: 10, seed: 5)
        let played = session.move(.left)

        let undone = session.undo()

        #expect(undone != nil)
        #expect(undone == played)
        #expect(session.board == board)
        #expect(session.score == 10)
        #expect(session.highScore == 22)
    }

    @Test func undoStopsAfterTheLimit() {
        let states = Self.play(5)
        var session = states[5]
        #expect(session.undoCount == GameSession.undoLimit)
        for back in 1...3 {
            #expect(session.undo() != nil)
            #expect(session.board == states[5 - back].board)
            #expect(session.score == states[5 - back].score)
            #expect(session.undoCount == 3 - back)
            #expect(session.redoCount == back)
        }
        let atLimit = session
        #expect(!session.canUndo)
        #expect(session.undo() == nil)
        #expect(session == atLimit)
    }

    @Test func fewerMovesThanTheLimitAllUndo() {
        let states = Self.play(2)
        var session = states[2]
        #expect(session.undoCount == 2)
        session.undo()
        session.undo()
        #expect(session.board == states[0].board)
        #expect(session.score == 0)
        #expect(!session.canUndo)
    }

    @Test func windowRollsWithEachMove() {
        let states = Self.play(8)
        for count in 3...8 {
            var session = states[count]
            #expect(session.undoCount == 3)
            for _ in 0..<3 { session.undo() }
            #expect(session.board == states[count - 3].board)
        }
    }

    /// Undo is usable again after moving: undo 3, redo 3, move, undo 3.
    @Test func undoWorksRepeatedly() {
        let states = Self.play(6)
        var session = states[3]
        for _ in 0..<3 { session.undo() }
        for _ in 0..<3 { session.redo() }
        #expect(session == states[3])
        for index in 4...6 {
            // Replaying the original game's swipes gives the same moves, since
            // the generator is back where it was.
            let direction = Self.direction(from: states[index - 1], to: states[index])
            session.move(direction)
            #expect(session == states[index])
        }
        for back in 1...3 {
            session.undo()
            #expect(session.board == states[6 - back].board)
        }
    }

    @Test func redoReplaysTheSameMovesInOrder() {
        let states = Self.play(5)
        var session = states[5]
        var undone: [Move] = []
        for _ in 0..<3 { undone.append(session.undo()!) }

        var redone: [Move] = []
        for index in 3...5 {
            redone.append(session.redo()!)
            #expect(session.board == states[index].board)
            #expect(session.score == states[index].score)
        }

        #expect(redone == undone.reversed())
        #expect(session == states[5])
        #expect(!session.canRedo)
        #expect(session.redo() == nil)
    }

    @Test func redoAfterPartialUndo() {
        let states = Self.play(5)
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
        let states = Self.play(6)
        for index in 1...6 {
            var session = states[index]
            session.undo()
            session.redo()
            #expect(session == states[index])
        }
    }

    @Test func swipeAfterUndoDrawsANewTileAndForgetsRedo() throws {
        let states = Self.play(5)
        var session = states[5]
        session.undo()
        session.undo()
        session.undo()

        let direction = Self.direction(from: states[2], to: states[3])
        let played = session.move(direction)
        let move = try #require(played)

        // The generator moved on, so the tile is drawn afresh (in this game it
        // lands differently from the undone move's).
        #expect(move.spawn != Self.move(from: states[2], to: states[3]).spawn)
        #expect(!session.canRedo)
        #expect(session.redo() == nil)
        #expect(session.undoCount == 1)
        session.undo()
        #expect(session.board == states[2].board)
        #expect(!session.canUndo, "the moves before the undone ones fell out of the window")
        #expect(session.redoCount == 1)
        let redone = session.redo()
        #expect(redone == move)
    }

    @Test func swipeAfterPartialUndoKeepsTheRemainingHistory() {
        let states = Self.play(5)
        var session = states[5]
        session.undo()
        session.undo()
        #expect(session.move(Self.direction(from: states[3], to: states[4])) != nil)
        #expect(session.undoCount == 2)
        #expect(session.redoCount == 0)
        session.undo()
        session.undo()
        #expect(session.board == states[2].board)
    }

    @Test func swipeThatChangesNothingKeepsRedo() throws {
        let board = try Board(rows: [[2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        var session = GameSession(rules: .classic, board: board, seed: 3)
        session.move(.right)
        session.undo()
        let afterUndo = session

        // Back on a board with one tile in the top-left corner, left and up
        // change nothing.
        #expect(session.move(.left) == nil)
        #expect(session.move(.up) == nil)

        #expect(session == afterUndo)
        #expect(session.canRedo)
    }

    @Test func undoAndRedoWorkFromGameOver() throws {
        var session = GameSession(
            rules: GameSessionTests.foursOnly, board: try Board(rows: GameSessionTests.oneMoveLeft), seed: 1)
        session.move(.left)
        let over = session
        #expect(session.isGameOver)

        #expect(session.undo() != nil)
        #expect(!session.isGameOver)
        #expect(session.board.rows == GameSessionTests.oneMoveLeft)
        #expect(session.redo() != nil)
        #expect(session == over)
    }

    @Test func restartClearsUndoAndRedo() {
        var session = Self.play(5)[5]
        session.undo()
        #expect(session.canUndo && session.canRedo)
        session.restart()
        #expect(!session.canUndo && !session.canRedo)
        #expect(session.undo() == nil)
        #expect(session.redo() == nil)
    }

    @Test func undoNeverLowersTheHighScore() {
        let states = Self.play(40)
        var session = states[40]
        let highScore = session.highScore
        #expect(highScore > states[37].score)
        for _ in 0..<3 { session.undo() }
        #expect(session.score == states[37].score)
        #expect(session.highScore == highScore)
    }

    /// The direction of the move from `before` to `after`.
    static func direction(from before: GameSession, to after: GameSession) -> Direction {
        Direction.allCases.first { direction in
            var copy = before
            return copy.move(direction) != nil && copy == after
        }!
    }

    /// The move from `before` to `after`.
    static func move(from before: GameSession, to after: GameSession) -> Move {
        var copy = before
        return copy.move(direction(from: before, to: after))!
    }
}
