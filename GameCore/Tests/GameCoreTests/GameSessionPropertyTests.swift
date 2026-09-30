import GameCore
import Testing

/// A deliberately different model of a session, as an oracle: it keeps every
/// state of the current line of play and a cursor into it, where the session
/// keeps a bounded undo stack and a redo stack. Undo moves the cursor back,
/// but never below `floor`, which trails the most recent move by the undo
/// limit; redo moves it forward again; a new move cuts off the states after
/// the cursor.
struct ReferenceSession {
    let rules: GameRules
    var generator: SplitMix64
    /// The states of the current line of play, from the start of the game.
    var states: [(board: Board, score: Int)]
    /// `moves[i]` leads from `states[i]` to `states[i + 1]`.
    var moves: [Move] = []
    /// The index of the current state.
    var cursor = 0
    /// The lowest index undo can reach.
    var floor = 0
    /// The largest score of any state ever reached.
    var bestScore: Int

    init(rules: GameRules, seed: UInt64, highScore: Int = 0) {
        self.rules = rules
        generator = SplitMix64(seed: seed)
        states = [(rules.startingBoard(using: &generator), 0)]
        bestScore = highScore
    }

    var board: Board { states[cursor].board }
    var score: Int { states[cursor].score }
    var undoCount: Int { cursor - floor }
    var redoCount: Int { states.count - 1 - cursor }

    mutating func move(_ direction: Direction) -> Move? {
        guard let move = rules.move(direction, on: board, using: &generator) else { return nil }
        let next = (move.board, score + move.scoreDelta)
        states.removeSubrange((cursor + 1)...)
        moves.removeSubrange(cursor...)
        states.append(next)
        moves.append(move)
        cursor += 1
        floor = max(floor, cursor - GameSession.undoLimit)
        bestScore = max(bestScore, score)
        return move
    }

    mutating func undo() -> Move? {
        guard cursor > floor else { return nil }
        cursor -= 1
        return moves[cursor]
    }

    mutating func redo() -> Move? {
        guard cursor < states.count - 1 else { return nil }
        cursor += 1
        return moves[cursor - 1]
    }

    mutating func restart() {
        states = [(rules.startingBoard(using: &generator), 0)]
        moves = []
        cursor = 0
        floor = 0
    }
}

struct GameSessionPropertyTests {
    enum Action {
        case move, undo, redo, restart
    }

    static let rules = [
        GameRules.classic,
        GameRules(id: "2x2", boardSize: 2),
        GameRules(id: "3x3", boardSize: 3),
        GameRules(id: "5x5", boardSize: 5, startingTileCount: 3),
    ]

    /// Random sequences of moves, undos, redos and restarts, compared with the
    /// reference model after every step.
    @Test(arguments: rules)
    func matchesTheReferenceModel(rules: GameRules) {
        for seed in 0..<25 as Range<UInt64> {
            var session = GameSession(rules: rules, seed: seed, highScore: 5)
            var model = ReferenceSession(rules: rules, seed: seed, highScore: 5)
            // Drives the choice of actions, separately from the games' generators.
            var chooser = SplitMix64(seed: seed &+ 1_000)
            for step in 0..<400 {
                let previousHighScore = session.highScore
                switch Self.randomAction(using: &chooser) {
                case .move:
                    let direction = Direction.allCases.randomElement(using: &chooser)!
                    #expect(session.move(direction) == model.move(direction), "step \(step)")
                case .undo:
                    #expect(session.undo() == model.undo(), "step \(step)")
                case .redo:
                    #expect(session.redo() == model.redo(), "step \(step)")
                case .restart:
                    session.restart()
                    model.restart()
                }
                #expect(session.board == model.board, "step \(step)")
                #expect(session.score == model.score)
                #expect(session.highScore == model.bestScore)
                #expect(session.highScore >= previousHighScore)
                #expect(session.undoCount == model.undoCount)
                #expect(session.redoCount == model.redoCount)
                #expect(session.canUndo == (model.undoCount > 0))
                #expect(session.canRedo == (model.redoCount > 0))
                #expect(session.undoCount + session.redoCount <= GameSession.undoLimit)
                #expect(session.isGameOver == !model.board.hasAvailableMoves)

                if session.canUndo {
                    var copy = session
                    copy.undo()
                    copy.redo()
                    #expect(copy == session, "undo then redo is the identity")
                }
                if session.canRedo {
                    var copy = session
                    copy.redo()
                    copy.undo()
                    #expect(copy == session, "redo then undo is the identity")
                }
            }
        }
    }

    /// Mostly moves, so games get long and the history fills up, with regular
    /// undos and redos and the occasional restart.
    static func randomAction(using generator: inout SplitMix64) -> Action {
        switch Int.random(in: 0..<100, using: &generator) {
        case 0..<55: .move
        case 55..<78: .undo
        case 78..<98: .redo
        default: .restart
        }
    }
}
