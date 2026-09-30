/// A square grid of tiles: the state of a game apart from its score.
///
/// ## Representation
///
/// Every tile holds a power of two, so each cell stores the tile's exponent in
/// a `UInt8` (0 is an empty cell, `e` is a tile of value 2^e), in row-major
/// order. This keeps boards small and cheap to compare and copy, makes an
/// invalid value unrepresentable, and turns a merge into `e + 1` with no
/// overflow checks. The public API speaks in tile values (`Int`) only.
///
/// Values go up to ``maxTileValue`` (2^62, the largest power of two an `Int`
/// holds with headroom). Two tiles of that value do not merge. This is
/// unreachable in play: tiles only grow by merging, and each move adds at most
/// one spawned tile, so a 2^62 tile takes more than 2^59 moves.
///
/// The board is a plain grid of values with no tile identities. Code that
/// animates tiles tracks identity itself from the ``TileMovement`` list of each
/// ``SlideResult``.
///
/// Positions use row 0 for the top row and column 0 for the leftmost column
/// (see ``Position``).
public struct Board: Hashable, Sendable {
    /// The number of rows, which equals the number of columns.
    public let size: Int

    /// Tile exponents in row-major order: 0 is empty, `e` is a tile of value 2^e.
    var cells: [UInt8]

    /// The largest tile value a board can hold, 2^62.
    public static let maxTileValue = 1 << Int(maxExponent)

    static let maxExponent: UInt8 = 62

    /// Creates an empty board with `size` rows and `size` columns.
    ///
    /// - Precondition: `size` is at least 1.
    public init(size: Int) {
        precondition(size > 0, "A board needs at least one cell")
        self.init(size: size, cells: Array(repeating: 0, count: size * size))
    }

    /// Creates a board from rows of tile values, top row first, where 0 is an
    /// empty cell.
    ///
    ///     let board = try Board(rows: [
    ///         [2, 0, 0, 2],
    ///         [0, 4, 0, 0],
    ///         [0, 0, 0, 0],
    ///         [8, 0, 0, 0],
    ///     ])
    ///
    /// - Throws: ``BoardError`` if there are no rows, the rows don't form a
    ///   square, or a value is neither 0 nor a power of two from 2 through
    ///   ``maxTileValue``.
    public init(rows: [[Int]]) throws(BoardError) {
        let size = rows.count
        guard size > 0 else { throw .noRows }
        var cells: [UInt8] = []
        cells.reserveCapacity(size * size)
        for (row, values) in rows.enumerated() {
            guard values.count == size else { throw .notSquare }
            for (column, value) in values.enumerated() {
                if value == 0 {
                    cells.append(0)
                } else if let exponent = Self.exponent(ofTileValue: value) {
                    cells.append(exponent)
                } else {
                    throw .invalidValue(value, at: Position(row: row, column: column))
                }
            }
        }
        self.init(size: size, cells: cells)
    }

    init(size: Int, cells: [UInt8]) {
        self.size = size
        self.cells = cells
    }

    /// The tile values row by row, top row first, with 0 for empty cells.
    ///
    /// `try Board(rows: board.rows)` reproduces the board.
    public var rows: [[Int]] {
        (0..<size).map { row in
            (0..<size).map { column in Self.value(ofExponent: cells[row * size + column]) }
        }
    }

    /// The value of the tile at `position`, or `nil` if the cell is empty.
    ///
    /// - Precondition: `position` is on the board.
    public subscript(position: Position) -> Int? {
        let exponent = cells[index(of: position)]
        return exponent == 0 ? nil : Self.value(ofExponent: exponent)
    }

    /// Whether `position` lies on the board.
    public func contains(_ position: Position) -> Bool {
        (0..<size).contains(position.row) && (0..<size).contains(position.column)
    }

    /// Every position on the board in row-major order.
    public var positions: [Position] {
        cells.indices.map(position(ofIndex:))
    }

    /// The empty positions in row-major order.
    public var emptyPositions: [Position] {
        cells.indices.filter { cells[$0] == 0 }.map(position(ofIndex:))
    }

    /// The number of tiles on the board.
    public var tileCount: Int {
        cells.count { $0 != 0 }
    }

    /// Whether every cell holds a tile.
    public var isFull: Bool {
        !cells.contains(0)
    }

    /// The value of the largest tile, or `nil` if the board is empty.
    public var highestTileValue: Int? {
        cells.max().flatMap { $0 == 0 ? nil : Self.value(ofExponent: $0) }
    }

    /// Whether some direction would change the board: a cell is empty or two
    /// orthogonally adjacent tiles can merge. The game is over when this is
    /// `false`.
    public var hasAvailableMoves: Bool {
        for row in 0..<size {
            for column in 0..<size {
                let index = row * size + column
                let exponent = cells[index]
                if exponent == 0 {
                    return true
                }
                if column + 1 < size, Self.canMerge(exponent, cells[index + 1]) {
                    return true
                }
                if row + 1 < size, Self.canMerge(exponent, cells[index + size]) {
                    return true
                }
            }
        }
        return false
    }

    func index(of position: Position) -> Int {
        precondition(contains(position), "\(position) is outside a \(size)×\(size) board")
        return position.row * size + position.column
    }

    func position(ofIndex index: Int) -> Position {
        Position(row: index / size, column: index % size)
    }

    /// Whether tiles with these exponents merge when they collide.
    static func canMerge(_ first: UInt8, _ second: UInt8) -> Bool {
        first != 0 && first == second && first < maxExponent
    }

    /// The tile value for an exponent, or 0 for an empty cell.
    static func value(ofExponent exponent: UInt8) -> Int {
        exponent == 0 ? 0 : 1 << Int(exponent)
    }

    /// The exponent of a valid tile value, or `nil` if `value` can't be a tile.
    static func exponent(ofTileValue value: Int) -> UInt8? {
        guard value >= 2, value <= maxTileValue, value & (value - 1) == 0 else { return nil }
        return UInt8(value.trailingZeroBitCount)
    }
}

extension Board: Codable {
    /// Decodes a board from its ``rows``, validated like ``init(rows:)``.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rows = try container.decode([[Int]].self)
        do {
            self = try Board(rows: rows)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid board: \(error)")
        }
    }

    /// Encodes the board as its ``rows``, for example `[[2,0],[0,4]]`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rows)
    }
}

extension Board: CustomStringConvertible {
    /// The board as a grid with one line per row and `.` for empty cells.
    public var description: String {
        let texts = rows.map { $0.map { $0 == 0 ? "." : String($0) } }
        let width = texts.joined().map(\.count).max() ?? 1
        return texts.map { row in
            row.map { String(repeating: " ", count: width - $0.count) + $0 }.joined(separator: " ")
        }.joined(separator: "\n")
    }
}

/// Why ``Board/init(rows:)`` rejected its input.
public enum BoardError: Error, Hashable, Sendable {
    /// There were no rows.
    case noRows
    /// Some row's length differs from the number of rows.
    case notSquare
    /// A value is neither 0 nor a power of two from 2 through ``Board/maxTileValue``.
    case invalidValue(Int, at: Position)
}
