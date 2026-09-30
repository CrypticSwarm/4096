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

    @Test(arguments: [GameRules.classic, fiveByFive, GameRules(id: "tiny", boardSize: 2, startingTileCount: 4)])
    func startingBoard(rules: GameRules) {
        var generator = SplitMix64(seed: 21)
        for _ in 0..<100 {
            let board = rules.startingBoard(using: &generator)
            #expect(board.size == rules.boardSize)
            #expect(board.tileCount == rules.startingTileCount)
            #expect(board.rows.joined().allSatisfy { [0, 2, 4].contains($0) })
        }
    }

    @Test func startingBoardIsDeterministicPerSeed() {
        var first = SplitMix64(seed: 4096)
        var second = SplitMix64(seed: 4096)
        let boards = (0..<20).map { _ in GameRules.classic.startingBoard(using: &first) }
        #expect(boards == (0..<20).map { _ in GameRules.classic.startingBoard(using: &second) })
        #expect(Set(boards).count > 1)
    }

    @Test(arguments: [
        (GameRules.classic, [[2048, 1024], [0, 0]], false),
        (GameRules.classic, [[4096, 0], [0, 0]], true),
        (GameRules.classic, [[2, 0], [0, 8192]], true),
        (GameRules.classic, [[0, 0], [0, 0]], false),
        (GameRules(id: "2048", winningValue: 2048), [[2048, 0], [0, 0]], true),
        (GameRules(id: "2048", winningValue: 2048), [[1024, 1024], [0, 0]], false),
        (fiveByFive, [[4096, 0], [0, 0]], false),
        (fiveByFive, [[8192, 0], [0, 0]], true),
    ])
    func isWon(rules: GameRules, rows: [[Int]], expected: Bool) throws {
        #expect(rules.isWon(try Board(rows: rows)) == expected)
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
        GameRules.classic, fiveByFive, GameRules(id: "custom", spawnDistribution: .init([.init(value: 4, weight: 1)])),
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
        #expect(GameRules.supportedBoardSizes == 2...16)
    }
}
