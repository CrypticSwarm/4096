import Foundation
import GameCore
import Testing

struct GameRulesTests {
    static let fiveByFive = GameRules(id: "5x5", boardSize: 5, winningValue: 8192, startingTileCount: 3)

    @Test func classicParameters() {
        let rules = GameRules.classic
        #expect(rules.id == "classic")
        #expect(rules.boardSize == 4)
        #expect(rules.winningValue == 4096)
        #expect(rules.startingTileCount == 2)
        #expect(rules.spawnDistribution == .classic)
        #expect(
            SpawnDistribution.classic.outcomes == [.init(value: 2, weight: 9), .init(value: 4, weight: 1)])
    }

    @Test(arguments: [
        GameRules.classic,
        fiveByFive,
        GameRules(id: "tiny", boardSize: 2, startingTileCount: 4),
        GameRules(id: "eights", boardSize: 3, spawnDistribution: .init(outcomes: [.init(value: 8, weight: 1)])),
    ])
    func startingBoard(rules: GameRules) {
        let allowed = Set(rules.spawnDistribution.outcomes.map(\.value))
        var generator = SplitMix64(seed: 21)
        for _ in 0..<100 {
            let board = rules.startingBoard(using: &generator)
            #expect(board.size == rules.boardSize)
            #expect(board.tileCount == rules.startingTileCount)
            #expect(board.rows.joined().allSatisfy { $0 == 0 || allowed.contains($0) })
        }
    }

    @Test func classicStartingTilesAreNinetyPercentTwos() {
        var generator = SplitMix64(seed: 2)
        let tiles = (0..<5_000).flatMap { _ in
            GameRules.classic.startingBoard(using: &generator).rows.joined().filter { $0 != 0 }
        }
        #expect(tiles.count == 10_000)
        #expect((850...1_150).contains(tiles.count { $0 == 4 }))  // expected 1000, σ = 30
    }

    @Test func acceptsOnlyBoardsOfItsSize() {
        #expect(GameRules.classic.accepts(Board(size: 4)))
        #expect(!GameRules.classic.accepts(Board(size: 5)))
        #expect(Self.fiveByFive.accepts(Board(size: 5)))
    }

    @Test func startingBoardIsDeterministicPerSeed() {
        var first = SplitMix64(seed: 4096)
        var second = SplitMix64(seed: 4096)
        let boards = (0..<20).map { _ in GameRules.classic.startingBoard(using: &first) }
        #expect(boards == (0..<20).map { _ in GameRules.classic.startingBoard(using: &second) })
        #expect(Set(boards).count > 1)
    }

    static let winCases: [(rules: GameRules, tiles: [Int], expected: Bool)] = [
        (GameRules.classic, [2048, 1024], false),
        (GameRules.classic, [4096], true),
        (GameRules.classic, [2, 0, 0, 8192], true),
        (GameRules.classic, [], false),
        (GameRules(id: "2048", winningValue: 2048), [2048], true),
        (GameRules(id: "2048", winningValue: 2048), [1024, 1024], false),
        (fiveByFive, [4096], false),
        (fiveByFive, [8192], true),
        (GameRules(id: "max", winningValue: Board.maxTileValue), [Board.maxTileValue / 2], false),
        (GameRules(id: "max", winningValue: Board.maxTileValue), [Board.maxTileValue], true),
    ]

    /// `tiles` fill the rules' board in row-major order; the rest is empty.
    @Test(arguments: winCases)
    func isWinning(rules: GameRules, tiles: [Int], expected: Bool) throws {
        let cells = tiles + Array(repeating: 0, count: rules.boardSize * rules.boardSize - tiles.count)
        let rows = (0..<rules.boardSize).map { Array(cells[($0 * rules.boardSize)...].prefix(rules.boardSize)) }
        #expect(rules.isWinning(try Board(rows: rows)) == expected)
    }

    @Test(arguments: 2...6)
    func stuckBoardsAreGameOver(size: Int) {
        let board = stuckBoard(size: size)
        #expect(!board.hasAvailableMoves)
        var generator = SplitMix64(seed: 0)
        let rules = GameRules(id: "\(size)", boardSize: size)
        for direction in Direction.allCases {
            #expect(rules.move(direction, on: board, using: &generator) == nil)
        }
    }

    @Test func fiveByFiveGameOverNeedsFullBoardWithoutPairs() throws {
        var rows = stuckBoard(size: 5).rows
        #expect(!(try Board(rows: rows)).hasAvailableMoves)
        rows[4][4] = 0
        #expect(try Board(rows: rows).hasAvailableMoves)
        rows[4][4] = rows[4][3]
        #expect(try Board(rows: rows).hasAvailableMoves)
        rows[4][4] = 8
        #expect(!(try Board(rows: rows)).hasAvailableMoves)
    }

    @Test(arguments: [
        GameRules.classic, fiveByFive,
        GameRules(id: "custom", spawnDistribution: .init(outcomes: [.init(value: 4, weight: 1)])),
    ])
    func codableRoundTrip(rules: GameRules) throws {
        #expect(try JSONDecoder().decode(GameRules.self, from: JSONEncoder().encode(rules)) == rules)
    }

    /// Guards the persisted format of the classic rules.
    @Test func decodesClassicFromStableJSON() throws {
        let json = """
            {"id":"classic","boardSize":4,"winningValue":4096,"startingTileCount":2,
             "spawnDistribution":{"outcomes":[{"value":2,"weight":9},{"value":4,"weight":1}]}}
            """
        #expect(try JSONDecoder().decode(GameRules.self, from: Data(json.utf8)) == .classic)
    }

    @Test(arguments: [
        (id: "", boardSize: 4, winningValue: 4096, startingTileCount: 2),
        (id: "x", boardSize: 1, winningValue: 4096, startingTileCount: 1),
        (id: "x", boardSize: 17, winningValue: 4096, startingTileCount: 2),
        (id: "x", boardSize: 4, winningValue: 4000, startingTileCount: 2),
        (id: "x", boardSize: 4, winningValue: 0, startingTileCount: 2),
        (id: "x", boardSize: 4, winningValue: 1, startingTileCount: 2),
        (id: "x", boardSize: 4, winningValue: 1 << 49, startingTileCount: 2),
        (id: "x", boardSize: 4, winningValue: 4096, startingTileCount: 0),
        (id: "x", boardSize: 4, winningValue: 4096, startingTileCount: 17),
    ])
    func decodingRejectsInvalidRules(id: String, boardSize: Int, winningValue: Int, startingTileCount: Int) {
        let json = """
            {"id":"\(id)","boardSize":\(boardSize),"winningValue":\(winningValue),
             "startingTileCount":\(startingTileCount),"spawnDistribution":{"outcomes":[{"value":2,"weight":1}]}}
            """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GameRules.self, from: Data(json.utf8))
        }
    }

    @Test func largestSupportedBoardsAreAccepted() throws {
        let json = """
            {"id":"x","boardSize":16,"winningValue":2,"startingTileCount":256,
             "spawnDistribution":{"outcomes":[{"value":2,"weight":1}]}}
            """
        let rules = try JSONDecoder().decode(GameRules.self, from: Data(json.utf8))
        var generator = SplitMix64(seed: 1)
        #expect(rules.startingBoard(using: &generator).isFull)
    }
}
