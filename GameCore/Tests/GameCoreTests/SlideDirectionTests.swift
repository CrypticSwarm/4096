import GameCore
import Testing

/// The same full board slid in each direction, plus symmetry between directions.
struct SlideDirectionTests {
    static let fixture = [
        [2, 2, 4, 0],
        [0, 4, 4, 4],
        [2, 0, 2, 8],
        [2, 2, 2, 2],
    ]

    static let expectations: [(direction: Direction, rows: [[Int]], score: Int)] = [
        (
            .left,
            [
                [4, 4, 0, 0],
                [8, 4, 0, 0],
                [4, 8, 0, 0],
                [4, 4, 0, 0],
            ],
            24
        ),
        (
            .right,
            [
                [0, 0, 4, 4],
                [0, 0, 4, 8],
                [0, 0, 4, 8],
                [0, 0, 4, 4],
            ],
            24
        ),
        (
            .up,
            [
                [4, 2, 8, 4],
                [2, 4, 4, 8],
                [0, 2, 0, 2],
                [0, 0, 0, 0],
            ],
            16
        ),
        (
            .down,
            [
                [0, 0, 0, 0],
                [0, 2, 0, 4],
                [2, 4, 8, 8],
                [4, 2, 4, 2],
            ],
            16
        ),
    ]

    @Test(arguments: expectations)
    func slidesFixture(direction: Direction, rows: [[Int]], score: Int) throws {
        let result = try Board(rows: Self.fixture).sliding(direction)
        #expect(result.board.rows == rows)
        #expect(result.scoreDelta == score)
        #expect(!result.isNoOp)
    }

    @Test func movementsFollowDirection() throws {
        let board = try Board(rows: [
            [0, 2, 0],
            [0, 2, 4],
            [8, 0, 4],
        ])
        let position = { Position(row: $0, column: $1) }

        let up = board.sliding(.up)
        #expect(up.board.rows == [[8, 4, 8], [0, 0, 0], [0, 0, 0]])
        #expect(
            up.movements == [
                TileMovement(from: position(0, 1), to: position(0, 1), value: 2, merged: true),
                TileMovement(from: position(1, 1), to: position(0, 1), value: 2, merged: true),
                TileMovement(from: position(1, 2), to: position(0, 2), value: 4, merged: true),
                TileMovement(from: position(2, 0), to: position(0, 0), value: 8, merged: false),
                TileMovement(from: position(2, 2), to: position(0, 2), value: 4, merged: true),
            ])
        #expect(
            up.merges == [TileMerge(position: position(0, 1), value: 4), TileMerge(position: position(0, 2), value: 8)])

        let right = board.sliding(.right)
        #expect(right.board.rows == [[0, 0, 2], [0, 2, 4], [0, 8, 4]])
        #expect(right.merges.isEmpty)
        #expect(
            right.movements == [
                TileMovement(from: position(0, 1), to: position(0, 2), value: 2, merged: false),
                TileMovement(from: position(1, 1), to: position(1, 1), value: 2, merged: false),
                TileMovement(from: position(1, 2), to: position(1, 2), value: 4, merged: false),
                TileMovement(from: position(2, 0), to: position(2, 1), value: 8, merged: false),
                TileMovement(from: position(2, 2), to: position(2, 2), value: 4, merged: false),
            ])
    }

    @Test(arguments: Direction.allCases)
    func stuckBoardIsNoOpEverywhere(direction: Direction) {
        let board = stuckBoard(size: 4)
        let result = board.sliding(direction)
        #expect(result.isNoOp)
        #expect(result.board == board)
        #expect(result.merges.isEmpty)
        #expect(result.movements.count == 16)
    }

    @Test(arguments: Direction.allCases, 1...6)
    func emptyBoardIsNoOp(direction: Direction, size: Int) {
        let result = Board(size: size).sliding(direction)
        #expect(result.isNoOp)
        #expect(result.movements.isEmpty)
        #expect(result.board == Board(size: size))
    }

    /// Rotating a board a quarter turn and sliding in the rotated direction is
    /// the same as sliding and then rotating, including the movement details.
    @Test(arguments: 2...6)
    func rotationSymmetry(size: Int) {
        var generator = SplitMix64(seed: UInt64(size))
        for _ in 0..<50 {
            let board = randomBoard(size: size, using: &generator)
            for direction in Direction.allCases {
                let result = board.sliding(direction)
                let rotated = rotated(board)
                let rotatedResult = rotated.sliding(direction.rotatedClockwise)

                #expect(rotatedResult.board == self.rotated(result.board))
                #expect(rotatedResult.scoreDelta == result.scoreDelta)
                let expectedMovements = result.movements.map {
                    TileMovement(
                        from: rotatedClockwise($0.from, size: size), to: rotatedClockwise($0.to, size: size),
                        value: $0.value, merged: $0.merged)
                }
                #expect(Set(rotatedResult.movements) == Set(expectedMovements))
                let expectedMerges = result.merges.map {
                    TileMerge(position: rotatedClockwise($0.position, size: size), value: $0.value)
                }
                #expect(Set(rotatedResult.merges) == Set(expectedMerges))
            }
        }
    }

    /// Mirroring a board left to right swaps the left and right slides.
    @Test(arguments: 2...6)
    func mirrorSymmetry(size: Int) {
        var generator = SplitMix64(seed: 100 + UInt64(size))
        for _ in 0..<50 {
            let board = randomBoard(size: size, using: &generator)
            let mirrored = try! Board(rows: board.rows.map { $0.reversed() })
            #expect(
                mirrored.sliding(.left).board.rows == board.sliding(.right).board.rows.map { $0.reversed() })
            #expect(
                mirrored.sliding(.right).board.rows == board.sliding(.left).board.rows.map { $0.reversed() })
        }
    }

    /// Every direction agrees with the reference single-line model applied to
    /// independently extracted lines.
    @Test(arguments: 1...7)
    func matchesReferenceModel(size: Int) {
        var generator = SplitMix64(seed: 200 + UInt64(size))
        for _ in 0..<100 {
            let board = randomBoard(size: size, emptyChance: 0.35, maxExponent: 3, using: &generator)
            for direction in Direction.allCases {
                let slid = lines(of: board.rows, toward: direction).map(referenceSlide)
                let result = board.sliding(direction)
                #expect(result.board.rows == rows(fromLines: slid.map(\.row), toward: direction))
                #expect(result.scoreDelta == slid.map(\.score).reduce(0, +))
            }
        }
    }

    private func rotated(_ board: Board) -> Board {
        try! Board(rows: rotatedClockwise(board.rows))
    }
}
