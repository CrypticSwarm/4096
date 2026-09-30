import GameCore
import Testing

/// Single-line behavior, checked on the first row of an otherwise empty board
/// whose size is the row's length, sliding left.
struct SlideLineTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let row: [Int]
        let expected: [Int]
        let score: Int
        var testDescription: String { "\(row) → \(expected)" }

        init(_ row: [Int], _ expected: [Int], score: Int = 0) {
            self.row = row
            self.expected = expected
            self.score = score
        }
    }

    static let cases: [Case] = [
        // Nothing to do.
        Case([0, 0, 0, 0], [0, 0, 0, 0]),
        Case([2, 0, 0, 0], [2, 0, 0, 0]),
        Case([2, 4, 8, 16], [2, 4, 8, 16]),
        Case([2, 4, 2, 4], [2, 4, 2, 4]),
        Case([4, 2, 0, 0], [4, 2, 0, 0]),
        // Sliding without merging.
        Case([0, 0, 0, 2], [2, 0, 0, 0]),
        Case([0, 2, 0, 4], [2, 4, 0, 0]),
        Case([2, 0, 4, 0], [2, 4, 0, 0]),
        Case([0, 4, 2, 4], [4, 2, 4, 0]),
        // One merge.
        Case([2, 2, 0, 0], [4, 0, 0, 0], score: 4),
        Case([2, 0, 0, 2], [4, 0, 0, 0], score: 4),
        Case([0, 0, 2, 2], [4, 0, 0, 0], score: 4),
        Case([0, 8, 0, 8], [16, 0, 0, 0], score: 16),
        Case([4, 2, 2, 0], [4, 4, 0, 0], score: 4),
        Case([8, 4, 2, 2], [8, 4, 4, 0], score: 4),
        Case([2, 4, 4, 2], [2, 8, 2, 0], score: 8),
        // Three equal tiles: the pair nearest the edge merges.
        Case([2, 2, 2, 0], [4, 2, 0, 0], score: 4),
        Case([0, 2, 2, 2], [4, 2, 0, 0], score: 4),
        Case([2, 0, 2, 2], [4, 2, 0, 0], score: 4),
        Case([2, 2, 0, 2], [4, 2, 0, 0], score: 4),
        Case([16, 16, 16, 0], [32, 16, 0, 0], score: 32),
        // Two merges.
        Case([2, 2, 2, 2], [4, 4, 0, 0], score: 8),
        Case([2, 2, 4, 4], [4, 8, 0, 0], score: 12),
        Case([4, 4, 2, 2], [8, 4, 0, 0], score: 12),
        // A merged tile doesn't merge again in the same move.
        Case([4, 4, 8, 0], [8, 8, 0, 0], score: 8),
        Case([2, 2, 4, 8], [4, 4, 8, 0], score: 4),
        Case([4, 2, 2, 8], [4, 4, 8, 0], score: 4),
        Case([8, 4, 4, 0], [8, 8, 0, 0], score: 8),
        // Other lengths (2×2 through 7×7 boards).
        Case([2, 2], [4, 0], score: 4),
        Case([0, 2], [2, 0]),
        Case([2, 4], [2, 4]),
        Case([2, 2, 2], [4, 2, 0], score: 4),
        Case([4, 0, 4], [8, 0, 0], score: 8),
        Case([2, 2, 2, 2, 2], [4, 4, 2, 0, 0], score: 8),
        Case([2, 0, 2, 0, 2], [4, 2, 0, 0, 0], score: 4),
        Case([4, 4, 2, 2, 4], [8, 4, 4, 0, 0], score: 12),
        Case([0, 0, 0, 0, 2], [2, 0, 0, 0, 0]),
        Case([2, 2, 2, 2, 2, 2], [4, 4, 4, 0, 0, 0], score: 12),
        Case([8, 8, 16, 0, 32, 32], [16, 16, 64, 0, 0, 0], score: 80),
        Case([2, 4, 8, 16, 32, 64], [2, 4, 8, 16, 32, 64]),
        Case([0, 0, 0, 0, 0, 0, 2], [2, 0, 0, 0, 0, 0, 0]),
        Case([2, 2, 4, 0, 4, 8, 8], [4, 8, 16, 0, 0, 0, 0], score: 28),
        // Large values, up to the largest tile, which never merges.
        Case([1 << 30, 1 << 30, 0, 0], [1 << 31, 0, 0, 0], score: 1 << 31),
        Case([1 << 61, 0, 1 << 61, 2], [1 << 62, 2, 0, 0], score: 1 << 62),
        Case([1 << 62, 1 << 62, 0, 0], [1 << 62, 1 << 62, 0, 0]),
        Case([0, 1 << 62, 0, 1 << 62], [1 << 62, 1 << 62, 0, 0]),
    ]

    @Test(arguments: cases)
    func slidesLeft(_ testCase: Case) throws {
        let size = testCase.row.count
        let emptyRows = Array(repeating: Array(repeating: 0, count: size), count: size - 1)
        let board = try Board(rows: [testCase.row] + emptyRows)

        let result = board.sliding(.left)

        #expect(result.board.rows == [testCase.expected] + emptyRows)
        #expect(result.scoreDelta == testCase.score)
        #expect(result.isNoOp == (testCase.row == testCase.expected))
    }

    @Test(arguments: cases)
    func referenceModelAgrees(_ testCase: Case) {
        // Guards the oracle used by the randomized tests.
        #expect(referenceSlide(testCase.row) == (testCase.expected, testCase.score))
    }

    @Test func threeEqualTilesMovements() throws {
        let board = try Board(rows: [[2, 2, 2, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])

        let result = board.sliding(.left)

        let position = { Position(row: 0, column: $0) }
        #expect(
            result.movements == [
                TileMovement(from: position(0), to: position(0), value: 2, merged: true),
                TileMovement(from: position(1), to: position(0), value: 2, merged: true),
                TileMovement(from: position(2), to: position(1), value: 2, merged: false),
            ])
        #expect(result.merges == [TileMerge(position: position(0), value: 4)])
    }

    @Test func mergeAcrossGapMovements() throws {
        let board = try Board(rows: [[0, 4, 0, 4], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 2]])

        let result = board.sliding(.left)

        #expect(
            result.movements == [
                TileMovement(
                    from: Position(row: 0, column: 1), to: Position(row: 0, column: 0), value: 4, merged: true),
                TileMovement(
                    from: Position(row: 0, column: 3), to: Position(row: 0, column: 0), value: 4, merged: true),
                TileMovement(
                    from: Position(row: 3, column: 3), to: Position(row: 3, column: 0), value: 2, merged: false),
            ])
        #expect(result.merges == [TileMerge(position: Position(row: 0, column: 0), value: 8)])
        #expect(result.scoreDelta == 8)
    }
}
