import GameCore
import Testing

struct GameSessionTests {
    /// A 3×3 variant that spawns only 4s, so the spawned value is known.
    static let foursOnly = GameRules(
        id: "fours", boardSize: 3, spawnDistribution: .init(outcomes: [.init(value: 4, weight: 1)]))
    /// Sliding left merges the 2s and frees one cell, and a 4 there leaves
    /// no moves: the last move of a game under ``foursOnly``.
    static let oneMoveLeft = [[2, 2, 8], [16, 4, 16], [4, 16, 4]]

    @Test(arguments: [GameRules.classic, GameRules(id: "5x5", boardSize: 5, startingTileCount: 3)])
    func newGameStartsWithTheRulesStartingBoard(rules: GameRules) {
        let session = GameSession(rules: rules, seed: 7, highScore: 12)
        var generator = SplitMix64(seed: 7)
        #expect(session.rules == rules)
        #expect(session.board == rules.startingBoard(using: &generator))
        #expect(session.score == 0)
        #expect(session.highScore == 12)
        #expect(!session.isGameOver)
    }

    @Test func sameSeedSameStart() {
        #expect(GameSession(rules: .classic, seed: 3) == GameSession(rules: .classic, seed: 3))
        #expect(GameSession(rules: .classic, seed: 3).board != GameSession(rules: .classic, seed: 4).board)
    }

    @Test func moveMatchesTheEngineAndAddsTheScore() throws {
        let board = try Board(rows: [[2, 2, 4, 4], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        var session = GameSession(rules: .classic, board: board, score: 10, seed: 5)
        var generator = SplitMix64(seed: 5)
        let expected = try #require(GameRules.classic.move(.left, on: board, using: &generator))

        let played = session.move(.left)

        let move = try #require(played)
        #expect(move == expected)
        #expect(session.board == move.board)
        #expect(session.score == 10 + 12)
        #expect(session.highScore == 22)
    }

    /// The generator carries over between moves: a session plays the same game
    /// as calling the engine with one generator throughout.
    @Test func movesDrawFromOneGenerator() {
        var session = GameSession(rules: .classic, seed: 11)
        var generator = SplitMix64(seed: 11)
        var board = GameRules.classic.startingBoard(using: &generator)
        var score = 0
        for index in 0..<200 {
            let direction = Direction.allCases[index % 4]
            let expected = GameRules.classic.move(direction, on: board, using: &generator)
            #expect(session.move(direction) == expected)
            if let expected {
                board = expected.board
                score += expected.scoreDelta
            }
            #expect(session.board == board)
            #expect(session.score == score)
        }
    }

    @Test(arguments: Direction.allCases)
    func swipeThatChangesNothingIsIgnored(direction: Direction) throws {
        let packed: [Direction: [[Int]]] = [
            .left: [[2, 4, 0], [8, 0, 0], [0, 0, 0]],
            .right: [[0, 4, 2], [0, 0, 8], [0, 0, 0]],
            .up: [[2, 8, 0], [4, 0, 0], [0, 0, 0]],
            .down: [[0, 0, 0], [4, 0, 0], [2, 8, 0]],
        ]
        var session = GameSession(
            rules: GameRules(id: "3x3", boardSize: 3), board: try Board(rows: packed[direction]!), seed: 1)
        let before = session

        #expect(session.move(direction) == nil)
        #expect(session == before)
    }

    @Test func highScoreFollowsTheScoreOnlyWhenBeaten() throws {
        let board = try Board(rows: [[2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        var session = GameSession(rules: .classic, board: board, seed: 1, highScore: 6)
        session.move(.left)
        #expect(session.score == 4)
        #expect(session.highScore == 6)

        session = GameSession(rules: .classic, board: board, score: 3, seed: 1, highScore: 6)
        session.move(.left)
        #expect(session.score == 7)
        #expect(session.highScore == 7)
    }

    @Test func highScoreIsAtLeastTheStartingScore() {
        let board = try! Board(rows: [[2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        #expect(GameSession(rules: .classic, board: board, score: 50, seed: 1, highScore: 20).highScore == 50)
    }

    @Test func gameOverWhenNoSwipeChangesTheBoard() throws {
        let rules = GameRules(id: "3x3", boardSize: 3)
        // Only the two 2s in the top row can merge.
        let board = try Board(rows: [[2, 2, 4], [4, 8, 16], [8, 16, 32]])
        #expect(!GameSession(rules: rules, board: board, seed: 1).isGameOver)
        #expect(GameSession(rules: rules, board: stuckBoard(size: 3), seed: 1).isGameOver)

        var session = GameSession(rules: rules, board: stuckBoard(size: 3), seed: 1)
        let before = session
        for direction in Direction.allCases {
            #expect(session.move(direction) == nil)
        }
        #expect(session == before)
    }

    @Test func gameOverAfterTheLastMove() throws {
        var session = GameSession(rules: Self.foursOnly, board: try Board(rows: Self.oneMoveLeft), seed: 1)

        let move = session.move(.left)

        #expect(move?.spawn == Spawn(position: at(0, 2), value: 4))
        #expect(session.board.rows == [[4, 8, 4], [16, 4, 16], [4, 16, 4]])
        #expect(session.isGameOver)
    }

    @Test(arguments: [GameRules.classic, GameRules(id: "5x5", boardSize: 5, startingTileCount: 3)])
    func restartStartsANewGameAndKeepsTheHighScore(rules: GameRules) {
        var session = GameSession(rules: rules, seed: 21)
        playUntilScored(&session)
        let highScore = session.highScore
        let oldBoard = session.board
        #expect(highScore > 0)

        session.restart()

        #expect(session.score == 0)
        #expect(session.highScore == highScore)
        #expect(session.board.tileCount == rules.startingTileCount)
        #expect(session.board != oldBoard)
        #expect(!session.isGameOver)
    }

    /// Restart draws from the session's generator, so each new game starts
    /// differently.
    @Test func restartsDrawNewStartingTiles() {
        var session = GameSession(rules: .classic, seed: 8)
        var starts = [session.board]
        for _ in 0..<5 {
            session.restart()
            starts.append(session.board)
        }
        #expect(Set(starts).count == starts.count)
    }

    @Test func restartIsReproducible() {
        var first = GameSession(rules: .classic, seed: 8)
        var second = first
        first.move(.left)
        second.move(.left)
        first.restart()
        second.restart()
        #expect(first == second)
    }

    @Test func scoreStopsAtIntMaxInsteadOfTrapping() throws {
        let board = try Board(rows: [[2, 2], [0, 0]])
        var session = GameSession(rules: GameRules(id: "2x2", boardSize: 2), board: board, score: .max - 1, seed: 1)
        session.move(.left)
        #expect(session.score == .max)
        #expect(session.highScore == .max)
    }
}
