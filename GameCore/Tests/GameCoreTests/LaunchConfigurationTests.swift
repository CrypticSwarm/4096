import GameCore
import Testing

struct LaunchConfigurationTests {
    @Test func noArgumentsMeansANewRandomGame() throws {
        let configuration = try LaunchConfiguration(arguments: ["/path/to/Game4096"])
        #expect(configuration == LaunchConfiguration())
        #expect(configuration.seed == nil)
        #expect(configuration.board == nil)
        #expect(configuration.score == 0)
        #expect(configuration.highScore == 0)
        #expect(configuration.storage == .standard)
        #expect(configuration.storage == .folder("Saves"))
        #expect(configuration.rules == .classic)
    }

    @Test func parsesSeedAndBoardAmongOtherArguments() throws {
        let configuration = try LaunchConfiguration(arguments: [
            "/path/to/Game4096", "-ApplePersistenceIgnoreState", "YES",
            "-seed", "18446744073709551615",
            "-board", "2,2,0,0;0,0,0,0;0,0,0,0;0,0,0,4",
        ])
        #expect(configuration.seed == UInt64.max)
        #expect(configuration.board == (try Board(rows: [[2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 4]])))
        #expect(configuration.rules == .classic)
    }

    @Test func lastOccurrenceWins() throws {
        let configuration = try LaunchConfiguration(arguments: ["-seed", "1", "-seed", "2"])
        #expect(configuration.seed == 2)
    }

    @Test func argumentsRoundTrip() throws {
        let configurations = [
            LaunchConfiguration(),
            LaunchConfiguration(seed: 0),
            LaunchConfiguration(board: try Board(notation: "2,0;0,4")),
            LaunchConfiguration(seed: 42, board: try Board(notation: "0,0,0;0,131072,0;0,0,2")),
            LaunchConfiguration(board: try Board(notation: "2,0;0,4"), score: 12, highScore: 40),
            LaunchConfiguration(highScore: 5, storage: .memory),
            LaunchConfiguration(seed: 1, storage: .folder("UITest-1234")),
        ]
        for configuration in configurations {
            #expect(try LaunchConfiguration(arguments: configuration.arguments) == configuration)
        }
        #expect(
            LaunchConfiguration(seed: 7, board: try Board(notation: "2,0;0,4")).arguments == [
                "-seed", "7", "-board", "2,0;0,4",
            ])
    }

    @Test func otherBoardSizesGetClassicRulesOnThatSize() throws {
        let configuration = LaunchConfiguration(
            board: try Board(notation: "2,0,0,0,0" + String(repeating: ";0,0,0,0,0", count: 4)))
        #expect(configuration.rules.boardSize == 5)
        #expect(configuration.rules.id == "classic-5x5")
        #expect(configuration.rules.winningValue == GameRules.classic.winningValue)
        #expect(configuration.rules.spawnDistribution == GameRules.classic.spawnDistribution)
        #expect(configuration.rules.accepts(configuration.board!))
    }

    @Test(arguments: [
        (["-seed"], LaunchConfigurationError.missingValue("-seed")),
        (["-board"], .missingValue("-board")),
        (["-seed", "-1"], .invalidSeed("-1")),
        (["-seed", "abc"], .invalidSeed("abc")),
        (["-seed", "18446744073709551616"], .invalidSeed("18446744073709551616")),
        (["-board", "2,x;0,0"], .invalidBoard("2,x;0,0", .unreadableValue("x"))),
        (["-board", "2,0;0"], .invalidBoard("2,0;0", .notSquare)),
        (["-board", "3,0;0,0"], .invalidBoard("3,0;0,0", .invalidValue(3, at: Position(row: 0, column: 0)))),
        (["-board", "2"], .invalidBoard("2", .unsupportedSize(1))),
        (["-board", "0,0;0,0"], .emptyBoard("0,0;0,0")),
        (["-board", "2,0;0,0", "-score"], .missingValue("-score")),
        (["-board", "2,0;0,0", "-score", "-4"], .invalidScore("-4")),
        (["-board", "2,0;0,0", "-score", "x"], .invalidScore("x")),
        (["-highScore", "1.5"], .invalidScore("1.5")),
        (["-score", "4"], .scoreWithoutBoard),
        (["-storage"], .missingValue("-storage")),
        (["-storage", ""], .invalidStorage("")),
        (["-storage", ".."], .invalidStorage("..")),
        (["-storage", "a/b"], .invalidStorage("a/b")),
        (["-storage", "/"], .invalidStorage("/")),
        (["-storage", "."], .invalidStorage(".")),
    ])
    func rejectsInvalidArguments(arguments: [String], error: LaunchConfigurationError) {
        #expect(throws: error) { try LaunchConfiguration(arguments: arguments) }
    }

    @Test func parsesScoresAndStorage() throws {
        let configuration = try LaunchConfiguration(arguments: [
            "-board", "2,0;0,4", "-score", "12", "-highScore", "40", "-storage", "memory",
        ])
        #expect(configuration.score == 12)
        #expect(configuration.highScore == 40)
        #expect(configuration.storage == .memory)
        #expect(try LaunchConfiguration(arguments: ["-storage", "Saves 2"]).storage == .folder("Saves 2"))
        #expect(try LaunchConfiguration(arguments: ["-storage", "UITest-8C1B"]).storage == .folder("UITest-8C1B"))
        #expect(LaunchConfiguration(storage: .memory).arguments == ["-storage", "memory"])
        #expect(LaunchConfiguration(storage: .standard).arguments.isEmpty)
    }
}

struct StartingSessionTests {
    static let board = try! Board(notation: "2,2,0,0;0,0,0,0;0,0,0,0;0,0,0,4")

    /// A store holding a saved classic game with a score and a high score of
    /// 100.
    static func storeWithSavedGame() throws -> (GameStore, GameSession) {
        let store = GameStore(storage: InMemoryGameStorage())
        var session = GameSession(rules: .classic, seed: 5, highScore: 100)
        playUntilScored(&session)
        session.undo()
        try store.save(session)
        return (store, session)
    }

    @Test func continuesTheSavedGame() throws {
        let (store, saved) = try Self.storeWithSavedGame()
        let session = try LaunchConfiguration(seed: 9).startingSession(from: store, randomSeed: 1)
        #expect(session == saved)
        #expect(session.canRedo)
    }

    @Test func startsANewGameFromTheSeedWithoutASavedGame() throws {
        let store = GameStore(storage: InMemoryGameStorage())
        let seeded = try LaunchConfiguration(seed: 9).startingSession(from: store, randomSeed: 1)
        #expect(seeded == GameSession(rules: .classic, seed: 9))
        let random = try LaunchConfiguration().startingSession(from: store, randomSeed: 1)
        #expect(random == GameSession(rules: .classic, seed: 1))
    }

    @Test func boardReplacesTheSavedGameAndKeepsTheHighScore() throws {
        let (store, _) = try Self.storeWithSavedGame()
        let configuration = LaunchConfiguration(seed: 9, board: Self.board, score: 20)
        let session = try configuration.startingSession(from: store, randomSeed: 1)
        #expect(session == GameSession(rules: .classic, board: Self.board, score: 20, seed: 9, highScore: 100))
    }

    @Test func highScoreArgumentOnlyRaisesTheHighScore() throws {
        let (store, saved) = try Self.storeWithSavedGame()
        let lower = try LaunchConfiguration(highScore: 50).startingSession(from: store, randomSeed: 1)
        #expect(lower.highScore == 100)
        let higher = try LaunchConfiguration(highScore: 500).startingSession(from: store, randomSeed: 1)
        #expect(higher.highScore == 500)
        #expect(higher.board == saved.board)
        #expect(higher.canRedo)
        let fixture = LaunchConfiguration(seed: 9, board: Self.board, highScore: 500)
        #expect(try fixture.startingSession(from: store, randomSeed: 1).highScore == 500)
    }

    @Test func newSessionIsTheFixtureOrANewGame() {
        #expect(LaunchConfiguration(seed: 3).newSession(randomSeed: 1) == GameSession(rules: .classic, seed: 3))
        #expect(
            LaunchConfiguration(board: Self.board, score: 8, highScore: 10).newSession(highScore: 30, randomSeed: 4)
                == GameSession(rules: .classic, board: Self.board, score: 8, seed: 4, highScore: 30))
    }

    @Test func readFailuresAreThrown() {
        let store = GameStore(storage: FailingStorage(failingKeys: nil))
        #expect(throws: FailingStorage.Failure.self) {
            try LaunchConfiguration().startingSession(from: store, randomSeed: 1)
        }
        #expect(throws: FailingStorage.Failure.self) {
            try LaunchConfiguration(board: Self.board).startingSession(from: store, randomSeed: 1)
        }
    }
}

struct BoardNotationTests {
    @Test func notationRoundTrips() throws {
        let board = try Board(rows: [[2, 0, 0], [0, 131072, 0], [0, 0, 4]])
        #expect(board.notation == "2,0,0;0,131072,0;0,0,4")
        #expect(try Board(notation: board.notation) == board)
        #expect(Board(size: 2).notation == "0,0;0,0")
    }

    @Test(arguments: [
        ("", BoardError.unreadableValue("")),
        ("2,0;0,4;", .unreadableValue("")),
        ("2,,0", .unreadableValue("")),
        ("2, 0;0,0", .unreadableValue(" 0")),
        ("2,0;0,4,0", .notSquare),
        ("2,0;0,6", .invalidValue(6, at: Position(row: 1, column: 1))),
    ])
    func rejectsMalformedNotation(notation: String, error: BoardError) {
        #expect(throws: error) { try Board(notation: notation) }
    }
}
