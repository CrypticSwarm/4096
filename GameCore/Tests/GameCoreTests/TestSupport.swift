import GameCore

/// Helpers shared by the engine tests. They are written independently of the
/// engine's internals so they can act as oracles.

/// A random board of the given size where each cell is empty with probability
/// `emptyChance` and otherwise holds a tile from 2 to 2^`maxExponent`. Small
/// exponents make merges and long merge chains common.
func randomBoard(
    size: Int, emptyChance: Double = 0.4, maxExponent: Int = 4, using generator: inout SplitMix64
) -> Board {
    let rows = (0..<size).map { _ in
        (0..<size).map { _ in
            Double.random(in: 0..<1, using: &generator) < emptyChance
                ? 0 : 1 << Int.random(in: 1...maxExponent, using: &generator)
        }
    }
    return try! Board(rows: rows)
}

/// A full board with no two orthogonally adjacent equal tiles (a checkerboard
/// of 2 and 4), on which no move is possible.
func stuckBoard(size: Int) -> Board {
    try! Board(rows: (0..<size).map { row in (0..<size).map { ($0 + row) % 2 == 0 ? 2 : 4 } })
}

/// The classic textbook 2048 row slide toward index 0: drop the gaps, merge
/// equal neighbors left to right skipping merged tiles, then pad with zeros.
/// Returns the new row and the points scored.
func referenceSlide(_ row: [Int]) -> (row: [Int], score: Int) {
    let tiles = row.filter { $0 != 0 }
    var result: [Int] = []
    var score = 0
    var index = 0
    while index < tiles.count {
        if index + 1 < tiles.count, tiles[index] == tiles[index + 1], tiles[index] < Board.maxTileValue {
            result.append(tiles[index] * 2)
            score += tiles[index] * 2
            index += 2
        } else {
            result.append(tiles[index])
            index += 1
        }
    }
    return (result + Array(repeating: 0, count: row.count - result.count), score)
}

/// The lines of `rows` in the order tiles move along them for `direction`:
/// each line starts at the edge the tiles move toward.
func lines(of rows: [[Int]], toward direction: Direction) -> [[Int]] {
    let columns = transposed(rows)
    switch direction {
    case .left: return rows
    case .right: return rows.map { $0.reversed() }
    case .up: return columns
    case .down: return columns.map { $0.reversed() }
    }
}

/// Inverse of `lines(of:toward:)`.
func rows(fromLines lines: [[Int]], toward direction: Direction) -> [[Int]] {
    switch direction {
    case .left: return lines
    case .right: return lines.map { $0.reversed() }
    case .up: return transposed(lines)
    case .down: return transposed(lines.map { $0.reversed() })
    }
}

func transposed(_ rows: [[Int]]) -> [[Int]] {
    rows.indices.map { column in rows.map { $0[column] } }
}

/// Rotates a square grid a quarter turn clockwise: the top row becomes the
/// rightmost column.
func rotatedClockwise(_ rows: [[Int]]) -> [[Int]] {
    let size = rows.count
    return (0..<size).map { row in (0..<size).map { column in rows[size - 1 - column][row] } }
}

/// Where `position` ends up when a board of `size` is rotated a quarter turn
/// clockwise.
func rotatedClockwise(_ position: Position, size: Int) -> Position {
    Position(row: position.column, column: size - 1 - position.row)
}

extension Direction {
    /// The direction after a quarter turn clockwise: up becomes right.
    var rotatedClockwise: Direction {
        switch self {
        case .up: .right
        case .right: .down
        case .down: .left
        case .left: .up
        }
    }
}

/// Shorthand for a position in test tables.
func at(_ row: Int, _ column: Int) -> Position {
    Position(row: row, column: column)
}

extension Board {
    /// The board rotated a quarter turn clockwise.
    var rotatedClockwise: Board {
        try! Board(rows: GameCoreTests.rotatedClockwise(rows))
    }

    /// The sum of all tile values.
    var tileSum: Int {
        rows.joined().reduce(0, +)
    }

    /// The positions holding tiles, row-major.
    var tilePositions: [Position] {
        positions.filter { self[$0] != nil }
    }
}
