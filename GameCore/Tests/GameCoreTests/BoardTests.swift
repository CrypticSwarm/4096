import Foundation
import GameCore
import Testing

struct BoardTests {
    @Test func emptyBoardHasNoTiles() {
        let board = Board(size: 5)
        #expect(board.size == 5)
        #expect(board.tileCount == 0)
        #expect(board.emptyPositions.count == 25)
        #expect(!board.isFull)
        #expect(board.highestTileValue == nil)
        #expect(board.rows == Array(repeating: Array(repeating: 0, count: 5), count: 5))
    }

    @Test func rowsRoundTripAndOrientation() throws {
        let rows = [
            [2, 0, 0, 4],
            [0, 8, 0, 0],
            [0, 0, 0, 0],
            [16, 0, 0, 1024],
        ]
        let board = try Board(rows: rows)
        #expect(board.rows == rows)
        #expect(board[Position(row: 0, column: 0)] == 2)
        #expect(board[Position(row: 0, column: 3)] == 4)
        #expect(board[Position(row: 1, column: 1)] == 8)
        #expect(board[Position(row: 3, column: 0)] == 16)
        #expect(board[Position(row: 3, column: 3)] == 1024)
        #expect(board[Position(row: 0, column: 1)] == nil)
        #expect(board.tileCount == 5)
        #expect(board.highestTileValue == 1024)
    }

    @Test func positionsAreRowMajor() throws {
        let board = try Board(rows: [[2, 0], [0, 0]])
        let expected = [
            Position(row: 0, column: 0), Position(row: 0, column: 1),
            Position(row: 1, column: 0), Position(row: 1, column: 1),
        ]
        #expect(board.positions == expected)
        #expect(board.emptyPositions == Array(expected.dropFirst()))
    }

    @Test func containsChecksBounds() {
        let board = Board(size: 3)
        #expect(board.contains(Position(row: 0, column: 0)))
        #expect(board.contains(Position(row: 2, column: 2)))
        #expect(!board.contains(Position(row: 3, column: 0)))
        #expect(!board.contains(Position(row: 0, column: -1)))
    }

    @Test func acceptsLargestTileValue() throws {
        let board = try Board(rows: [[Board.maxTileValue, 0], [0, 0]])
        #expect(board.highestTileValue == Board.maxTileValue)
        #expect(Board.maxTileValue == 1 << 48)
    }

    @Test(arguments: [
        ([[Int]](), BoardError.unsupportedSize(0)),
        (Array(repeating: Array(repeating: 0, count: 17), count: 17), .unsupportedSize(17)),
        ([[1 << 49, 0], [0, 0]], .invalidValue(1 << 49, at: Position(row: 0, column: 0))),
        ([[2, 0], [0]], .notSquare),
        ([[2, 0, 0], [0, 0, 0]], .notSquare),
        ([[2, 3], [0, 0]], .invalidValue(3, at: Position(row: 0, column: 1))),
        ([[2, 0], [1, 0]], .invalidValue(1, at: Position(row: 1, column: 0))),
        ([[2, 0], [0, -2]], .invalidValue(-2, at: Position(row: 1, column: 1))),
        ([[Int.min, 0], [0, 0]], .invalidValue(Int.min, at: Position(row: 0, column: 0))),
        ([[0, 6], [0, 0]], .invalidValue(6, at: Position(row: 0, column: 1))),
    ])
    func rejectsInvalidRows(rows: [[Int]], error: BoardError) {
        #expect(throws: error) { try Board(rows: rows) }
    }

    @Test func fullBoard() throws {
        let board = try Board(rows: [[2, 4], [8, 16]])
        #expect(board.isFull)
        #expect(board.emptyPositions.isEmpty)
    }

    @Test(arguments: [
        ([[2, 4], [8, 16]], false),
        ([[2, 4], [8, 0]], true),
        ([[2, 2], [8, 16]], true),  // horizontal pair
        ([[2, 4], [2, 16]], true),  // vertical pair
        ([[2, 4], [4, 2]], false),  // equal only diagonally
        ([[2, 4, 2], [4, 2, 4], [2, 4, 2]], false),
        ([[2, 4, 2], [4, 2, 4], [2, 4, 4]], true),  // pair in the last row
        ([[2, 4, 2], [4, 2, 4], [4, 4, 2]], true),
        ([[2, 4, 8], [4, 2, 16], [2, 4, 16]], true),  // pair in the last column
        ([[Board.maxTileValue, Board.maxTileValue], [2, 4]], false),  // largest tiles never merge
        ([[2]], false),
        ([[0]], true),
    ])
    func hasAvailableMoves(rows: [[Int]], expected: Bool) throws {
        #expect(try Board(rows: rows).hasAvailableMoves == expected)
    }

    @Test func descriptionAlignsColumns() throws {
        let board = try Board(rows: [[2, 0], [128, 4]])
        #expect(board.description == "  2   .\n128   4")
    }

    @Test func largestBoardIsAccepted() throws {
        let board = try Board(rows: Array(repeating: Array(repeating: 2, count: 16), count: 16))
        #expect(board.size == Board.maxSize)
        #expect(Board(size: 16).size == 16)
    }

    /// The limits keep sums far from overflow: the largest board full of
    /// tiles of half the maximum value merges them all in one slide.
    @Test func largestSumsDontOverflow() throws {
        let almostMax = Board.maxTileValue / 2
        let board = try Board(rows: Array(repeating: Array(repeating: almostMax, count: 16), count: 16))
        let result = board.sliding(.left)
        #expect(result.merges.count == 128)
        #expect(result.scoreDelta == 128 * Board.maxTileValue)
        #expect(result.board.tileSum == board.tileSum)
        #expect(result.board.sliding(.left).isNoOp)  // tiles at the maximum don't merge
        let full = try Board(rows: Array(repeating: Array(repeating: Board.maxTileValue, count: 16), count: 16))
        #expect(!full.hasAvailableMoves)
        #expect(Direction.allCases.allSatisfy { full.sliding($0).isNoOp })
    }

    @Test func codableRoundTrip() throws {
        let board = try Board(rows: [[2, 0, 4], [0, 1 << 20, 0], [Board.maxTileValue, 0, 2]])
        let data = try JSONEncoder().encode(board)
        #expect(try JSONDecoder().decode(Board.self, from: data) == board)
    }

    @Test func encodesAsRows() throws {
        let board = try Board(rows: [[2, 0], [0, 4]])
        let json = String(decoding: try JSONEncoder().encode(board), as: UTF8.self)
        #expect(json == "[[2,0],[0,4]]")
    }

    @Test(arguments: ["[]", "[[2,0],[0]]", "[[3,0],[0,0]]", "{\"rows\":[[2]]}"])
    func decodingRejectsInvalidBoards(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Board.self, from: Data(json.utf8))
        }
    }

    @Test(arguments: [
        Position(row: 0, column: 0), Position(row: 3, column: 7), Position(row: -1, column: 2),
    ])
    func positionCodableRoundTrip(position: Position) throws {
        let data = try JSONEncoder().encode(position)
        #expect(try JSONDecoder().decode(Position.self, from: data) == position)
    }

    /// Guards the persisted format of positions.
    @Test func positionEncodesAsRowAndColumn() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(Position(row: 2, column: 3)), as: UTF8.self)
        #expect(json == #"{"column":3,"row":2}"#)
        #expect(try JSONDecoder().decode(Position.self, from: Data(json.utf8)) == Position(row: 2, column: 3))
    }

    @Test(arguments: Direction.allCases)
    func directionEncodesAsStableName(direction: Direction) throws {
        let data = try JSONEncoder().encode([direction])
        #expect(String(decoding: data, as: UTF8.self) == "[\"\(direction.rawValue)\"]")
        #expect(try JSONDecoder().decode([Direction].self, from: data) == [direction])
    }

    @Test func directionRawValues() {
        #expect(Direction.allCases.map(\.rawValue) == ["up", "down", "left", "right"])
    }
}
