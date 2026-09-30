import GameCore
import Testing

struct MoveTests {
    @Test func moveSlidesThenSpawnsInAnEmptyCell() throws {
        let board = try Board(rows: [[2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 4]])
        var generator = SplitMix64(seed: 1)

        let move = try #require(GameRules.classic.move(.left, on: board, using: &generator))

        #expect(move.direction == .left)
        #expect(move.slide == board.sliding(.left))
        #expect(move.slide.board.rows == [[4, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [4, 0, 0, 0]])
        #expect(move.slide.board.canPlace(move.spawn))
        #expect(move.board == move.slide.board.placing(move.spawn))
        #expect(move.scoreDelta == 4)
    }

    @Test(arguments: Direction.allCases)
    func noOpIsNotAMoveAndDrawsNothing(direction: Direction) throws {
        let packed: [Direction: [[Int]]] = [
            .left: [[2, 4, 0], [8, 0, 0], [0, 0, 0]],
            .right: [[0, 4, 2], [0, 0, 8], [0, 0, 0]],
            .up: [[2, 8, 0], [4, 0, 0], [0, 0, 0]],
            .down: [[0, 0, 0], [4, 0, 0], [2, 8, 0]],
        ]
        let board = try Board(rows: packed[direction]!)
        var generator = SplitMix64(seed: 9)
        let before = generator

        #expect(GameRules.classic.move(direction, on: board, using: &generator) == nil)
        #expect(generator == before)
        #expect(
            Move(direction: direction, spawn: Spawn(position: Position(row: 2, column: 2), value: 2), on: board) == nil)
    }

    @Test func replayReproducesTheMove() throws {
        let board = try Board(rows: [[2, 0, 2, 4], [0, 4, 0, 4], [8, 8, 8, 0], [0, 0, 0, 2]])
        var generator = SplitMix64(seed: 31)
        for direction in Direction.allCases {
            let move = try #require(GameRules.classic.move(direction, on: board, using: &generator))
            #expect(Move(direction: direction, spawn: move.spawn, on: board) == move)
        }
    }

    @Test func replayUsesTheRecordedSpawn() throws {
        let board = try Board(rows: [[2, 2, 0], [0, 0, 0], [0, 0, 0]])
        let spawn = Spawn(position: Position(row: 2, column: 1), value: 4)

        let move = try #require(Move(direction: .left, spawn: spawn, on: board))

        #expect(move.board.rows == [[4, 0, 0], [0, 0, 0], [0, 4, 0]])
        #expect(move.spawn == spawn)
        #expect(move.scoreDelta == 4)
    }

    @Test(arguments: [
        Spawn(position: Position(row: 0, column: 0), value: 2),  // occupied after the slide
        Spawn(position: Position(row: 0, column: 1), value: 2),  // freed by the slide, but taken again
        Spawn(position: Position(row: 3, column: 0), value: 2),  // off the board
        Spawn(position: Position(row: 2, column: 2), value: 6),  // invalid value
    ])
    func replayRejectsSpawnsThatDontFit(spawn: Spawn) throws {
        // Sliding left gives [[4, 2, 0], [0, 0, 0], [0, 0, 0]].
        let board = try Board(rows: [[2, 2, 2], [0, 0, 0], [0, 0, 0]])
        #expect(Move(direction: .left, spawn: spawn, on: board) == nil)
    }

    /// Plays whole games with random swipes and checks every step.
    ///
    /// The score is checked against the board through a closed form: building
    /// a tile of 2^k from 2s scores (k - 1) · 2^k, and a spawned tile of 2^j
    /// arrives with none of the (j - 1) · 2^j points it would have scored if
    /// built. So score == potential(board) - Σ potential(spawned values).
    @Test(arguments: [
        GameRules.classic,
        GameRules(id: "3x3", boardSize: 3, winningValue: 64),
        GameRules(id: "5x5", boardSize: 5, startingTileCount: 3),
        GameRules(
            id: "6x6", boardSize: 6, spawnDistribution: .init([.init(value: 2, weight: 1), .init(value: 8, weight: 1)])),
    ])
    func playedGamesKeepInvariants(rules: GameRules) {
        func potential(_ value: Int) -> Int { (value.trailingZeroBitCount - 1) * value }
        func potential(_ board: Board) -> Int { board.rows.joined().filter { $0 != 0 }.map(potential).reduce(0, +) }

        let allowedSpawns = Set(rules.spawnDistribution.outcomes.map(\.value))
        for seed in 0..<20 as Range<UInt64> {
            var generator = SplitMix64(seed: seed)
            var board = rules.startingBoard(using: &generator)
            var score = 0
            var spawnedPotential = potential(board)
            var moves = 0
            while board.hasAvailableMoves && moves < 5_000 {
                let direction = Direction.allCases.randomElement(using: &generator)!
                guard let move = rules.move(direction, on: board, using: &generator) else {
                    #expect(board.sliding(direction).isNoOp)
                    continue
                }
                #expect(allowedSpawns.contains(move.spawn.value))
                #expect(move.slide.board.canPlace(move.spawn))
                #expect(move.board.tileSum == board.tileSum + move.spawn.value)
                #expect(move.board.tileCount == board.tileCount - move.slide.merges.count + 1)
                #expect(Move(direction: direction, spawn: move.spawn, on: board) == move)
                #expect(rules.isWon(move.board) == (move.board.highestTileValue! >= rules.winningValue))
                score += move.scoreDelta
                spawnedPotential += potential(move.spawn.value)
                #expect(score == potential(move.board) - spawnedPotential)
                moves += 1
                board = move.board
            }
            #expect(!board.hasAvailableMoves, "games end in a few thousand moves")
            #expect(board.isFull)
            #expect(Direction.allCases.allSatisfy { rules.move($0, on: board, using: &generator) == nil })
        }
    }

    @Test func sameSeedSameGame() {
        func play(seed: UInt64) -> (board: Board, score: Int, moves: [Move]) {
            var generator = SplitMix64(seed: seed)
            var board = GameRules.classic.startingBoard(using: &generator)
            var score = 0
            var moves: [Move] = []
            for index in 0..<300 {
                let direction = Direction.allCases[index % 4]
                if let move = GameRules.classic.move(direction, on: board, using: &generator) {
                    moves.append(move)
                    score += move.scoreDelta
                    board = move.board
                }
            }
            return (board, score, moves)
        }
        let first = play(seed: 2026)
        let second = play(seed: 2026)
        #expect(first.board == second.board)
        #expect(first.score == second.score)
        #expect(first.moves == second.moves)
        #expect(first.moves != play(seed: 2027).moves)
    }
}
