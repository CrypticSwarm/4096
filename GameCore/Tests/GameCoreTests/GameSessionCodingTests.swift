import Foundation
import GameCore
import Testing

struct GameSessionCodingTests {
    static func roundTripped(_ session: GameSession) throws -> GameSession {
        try JSONDecoder().decode(GameSession.self, from: JSONEncoder().encode(session))
    }

    @Test func roundTripRestoresHistoryAndContinuesIdentically() throws {
        var original = midGame()
        var restored = try Self.roundTripped(original)
        #expect(restored == original)
        #expect(restored.undoCount == 1 && restored.redoCount == 2)

        #expect(restored.redo() == original.redo())
        #expect(restored.redo() == original.redo())
        restored.undo()
        original.undo()
        #expect(restored == original)
        for index in 0..<50 {
            let direction = Direction.allCases[index % 4]
            #expect(restored.move(direction) == original.move(direction), "same tiles drawn")
        }
        restored.restart()
        original.restart()
        #expect(restored == original)
    }

    @Test func pendingWinSurvivesARoundTrip() throws {
        var session = try WinTests.session(WinTests.oneMergeFromEight)
        session.move(.left)
        #expect(try Self.roundTripped(session).shouldPresentWin)
        session.acknowledgeWin()
        let restored = try Self.roundTripped(session)
        #expect(restored.hasWon && !restored.shouldPresentWin)
    }

    static func jsonObject(_ session: GameSession) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as! [String: Any]
    }

    /// Encodes `session` and lets `edit` change the JSON object before
    /// decoding it again.
    static func decodeEdited(_ session: GameSession, _ edit: (inout [String: Any]) -> Void) throws -> GameSession {
        var object = try jsonObject(session)
        edit(&object)
        return try JSONDecoder().decode(GameSession.self, from: JSONSerialization.data(withJSONObject: object))
    }

    typealias Edit = @Sendable (inout [String: Any]) -> Void

    /// The sessions the invalid edits start from.
    enum Base: Sendable {
        /// No history, a score of 8 and a high score of 20.
        case fresh
        /// One move that scores 12 and can be undone, from `fresh`.
        case oneMove
        /// Three moves that can be undone and none to redo.
        case undoOnly
        /// ``midGame()``: one move to undo and two to redo.
        case midGame

        var session: GameSession {
            let board = try! Board(rows: [[2, 2, 4, 4], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
            var session = GameSession(rules: .classic, board: board, score: 8, seed: 1, highScore: 20)
            switch self {
            case .fresh: return session
            case .oneMove:
                session.move(.left)
                return session
            case .undoOnly: return playedGame(moves: 12).states[12]
            case .midGame: return GameCoreTests.midGame()
            }
        }
    }

    /// Edits that make a session inconsistent, each caught by a different
    /// check.
    static let invalidEdits: [(problem: String, base: Base, edit: Edit)] = [
        ("board of another size", .fresh, { $0["board"] = [[2, 0, 0], [0, 0, 0], [0, 0, 0]] }),
        ("negative score", .fresh, { $0["score"] = -4 }),
        ("high score below score", .fresh, { $0["highScore"] = 4 }),
        ("unknown win state", .fresh, { $0["win"] = "maybe" }),
        ("missing generator", .fresh, { $0["generator"] = nil }),
        (
            "negative score before a move",
            .oneMove,
            {
                $0["score"] = 0
                $0["undo"] = editing($0["undo"], at: 0) { entry in
                    entry["before"] = editing(entry["before"]) { $0["score"] = -12 }
                }
            }
        ),
        (
            "undo entries that don't follow each other",
            .undoOnly,
            {
                let other = try! JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(playedGame(moves: 12, seed: 5).states[12]))
                $0["undo"] = editing($0["undo"], at: 0) {
                    $0 = ((other as! [String: Any])["undo"] as! [[String: Any]])[0]
                }
            }
        ),
        (
            "undo history that doesn't lead to the board",
            .undoOnly,
            {
                $0["score"] = ($0["score"] as! Int) + 2
                $0["highScore"] = ($0["highScore"] as! Int) + 2
            }
        ),
        (
            "undo entry whose move doesn't replay",
            .undoOnly,
            {
                $0["undo"] = editing($0["undo"], at: 2) { entry in
                    entry["move"] = editing(entry["move"]) {
                        $0["spawn"] = ["position": ["row": 9, "column": 9], "value": 2]
                    }
                }
            }
        ),
        ("empty board", .fresh, { $0["board"] = Board(size: 4).rows }),
        (
            "redo move that doesn't fit",
            .midGame,
            {
                $0["redo"] = editing($0["redo"], at: 0) {
                    $0["spawn"] = ["position": ["row": 9, "column": 9], "value": 2]
                }
            }
        ),
    ]

    @Test(arguments: invalidEdits)
    func decodingRejectsInconsistentGames(problem: String, base: Base, edit: Edit) throws {
        let session = base.session
        #expect(try Self.decodeEdited(session) { _ in } == session)
        #expect(throws: DecodingError.self, "\(problem)") {
            try Self.decodeEdited(session, edit)
        }
    }

    /// Four undo entries that follow each other and lead to the board are
    /// still one too many.
    @Test func decodingRejectsAHistoryLongerThanTheLimit() throws {
        let states = playedGame(moves: 4).states
        let firstEntry = try Self.jsonObject(states[1])["undo"] as! [Any]
        let lastEntries = try Self.jsonObject(states[4])["undo"] as! [Any]
        #expect(throws: DecodingError.self) {
            try Self.decodeEdited(states[4]) { $0["undo"] = firstEntry + lastEntries }
        }
    }

    /// Three moves to redo and the move before them to undo follow each
    /// other, but are one more than the limit.
    @Test func decodingRejectsUndoAndRedoBeyondTheLimit() throws {
        let states = playedGame(moves: 4).states
        var session = states[4]
        for _ in 0..<3 { session.undo() }
        #expect(session.board == states[1].board && session.redoCount == 3)
        let entry = try Self.jsonObject(states[1])["undo"] as! [Any]
        #expect(throws: DecodingError.self) {
            try Self.decodeEdited(session) { $0["undo"] = entry }
        }
    }

    @Test func decodingRejectsAHighScoreBelowAScoreToRedo() throws {
        var session = playedGame(moves: 40).states[40]
        for _ in 0..<3 { session.undo() }
        #expect(try Self.decodeEdited(session) { _ in } == session)
        #expect(throws: DecodingError.self) {
            try Self.decodeEdited(session) { $0["highScore"] = session.score }
        }
    }

    @Test func decodingRejectsAnUnwonGameWithAWinningTile() throws {
        let session = GameSession(
            rules: WinTests.toEight, board: try Board(rows: [[8, 0, 0], [0, 0, 0], [0, 0, 0]]), seed: 1)
        #expect(try Self.decodeEdited(session) { _ in }.shouldPresentWin)
        #expect(throws: DecodingError.self) {
            try Self.decodeEdited(session) { $0["win"] = "notWon" }
        }
    }
}

/// `object`, a JSON object, after `edit`.
private func editing(_ object: Any?, _ edit: (inout [String: Any]) -> Void) -> [String: Any] {
    var object = object as! [String: Any]
    edit(&object)
    return object
}

/// `array`, a JSON array of objects, after `edit` changes the element at `index`.
private func editing(_ array: Any?, at index: Int, _ edit: (inout [String: Any]) -> Void) -> [[String: Any]] {
    var array = array as! [[String: Any]]
    edit(&array[index])
    return array
}
