import GameCore
import Testing

struct LaunchConfigurationTests {
    @Test func noArgumentsMeansANewRandomGame() throws {
        let configuration = try LaunchConfiguration(arguments: ["/path/to/Game4096"])
        #expect(configuration == LaunchConfiguration())
        #expect(configuration.seed == nil)
        #expect(configuration.board == nil)
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
        let configuration = LaunchConfiguration(board: Board(size: 5))
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
    ])
    func rejectsInvalidArguments(arguments: [String], error: LaunchConfigurationError) {
        #expect(throws: error) { try LaunchConfiguration(arguments: arguments) }
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
