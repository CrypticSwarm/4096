import Foundation
import GameCore
import Testing

/// A deliberately different model of a session, as an oracle: it keeps every
/// state of the current line of play and a cursor into it, where the session
/// keeps a bounded undo stack and a redo stack. Undo moves the cursor back,
/// but never below `floor`, which trails the most recent move by the undo
/// limit; redo moves it forward again; a new move cuts off the states after
/// the cursor.
///
/// Winning is modeled from the largest tile ever reached in the game: the win
/// is pending from the action that first reached a winning tile until it is
/// acknowledged.
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
    /// The largest tile reached in this game, in any state.
    var largestTile: Int
    /// Whether a winning tile was reached and the win hasn't been acknowledged
    /// since.
    var winPending: Bool

    init(rules: GameRules, seed: UInt64, highScore: Int = 0) {
        self.rules = rules
        generator = SplitMix64(seed: seed)
        states = [(rules.startingBoard(using: &generator), 0)]
        bestScore = highScore
        largestTile = states[0].board.highestTileValue ?? 0
        winPending = largestTile >= rules.winningValue
    }

    var board: Board { states[cursor].board }
    var score: Int { states[cursor].score }
    var undoCount: Int { cursor - floor }
    var redoCount: Int { states.count - 1 - cursor }
    var hasWon: Bool { largestTile >= rules.winningValue }

    /// Updates the win and best score after an action that changed the state.
    mutating func reached(_ board: Board, score: Int) {
        let wasWon = hasWon
        largestTile = max(largestTile, board.highestTileValue ?? 0)
        if hasWon && !wasWon {
            winPending = true
        }
        bestScore = max(bestScore, score)
    }

    mutating func move(_ direction: Direction) -> Move? {
        guard let move = rules.move(direction, on: board, using: &generator) else { return nil }
        let next = (move.board, score + move.scoreDelta)
        states.removeSubrange((cursor + 1)...)
        moves.removeSubrange(cursor...)
        states.append(next)
        moves.append(move)
        cursor += 1
        floor = max(floor, cursor - GameSession.undoLimit)
        reached(board, score: score)
        return move
    }

    mutating func undo() -> Bool {
        guard cursor > floor else { return false }
        cursor -= 1
        return true
    }

    mutating func redo() -> Move? {
        guard cursor < states.count - 1 else { return nil }
        cursor += 1
        reached(board, score: score)
        return moves[cursor - 1]
    }

    mutating func restart() {
        states = [(rules.startingBoard(using: &generator), 0)]
        moves = []
        cursor = 0
        floor = 0
        largestTile = 0
        winPending = false
        reached(board, score: 0)
    }
}

struct GameSessionPropertyTests {
    enum Action {
        case move, undo, redo, acknowledgeWin, restart
    }

    static let rules = [
        GameRules.classic,
        GameRules(id: "2x2-to16", boardSize: 2, winningValue: 16),
        GameRules(id: "3x3-to64", boardSize: 3, winningValue: 64),
        GameRules(id: "5x5", boardSize: 5, startingTileCount: 3),
    ]

    /// Random sequences of moves, undos, redos, acknowledged wins and
    /// restarts, compared with the reference model after every step. Every
    /// state also survives encoding.
    @Test(arguments: rules)
    func matchesTheReferenceModel(rules: GameRules) throws {
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
                case .acknowledgeWin:
                    session.acknowledgeWin()
                    model.winPending = false
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
                #expect(session.isGameOver == Direction.allCases.allSatisfy { model.board.sliding($0).isNoOp })
                #expect(session.hasWon == model.hasWon)
                #expect(session.shouldPresentWin == model.winPending)
                #expect(try JSONDecoder().decode(GameSession.self, from: JSONEncoder().encode(session)) == session)

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
        case 55..<74: .undo
        case 74..<90: .redo
        case 90..<98: .acknowledgeWin
        default: .restart
        }
    }
}
