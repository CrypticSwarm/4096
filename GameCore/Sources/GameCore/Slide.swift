/// Where one tile went during a slide.
public struct TileMovement: Hashable, Sendable {
    /// The tile's position before the move.
    public let from: Position
    /// The tile's position after the move; equal to ``from`` if it stayed put.
    public let to: Position
    /// The tile's value before the move.
    public let value: Int
    /// Whether the tile merged with another tile at ``to``.
    ///
    /// Both tiles of a merge are flagged and move to the same cell, which then
    /// holds one tile of twice their value (listed in ``SlideResult/merges``).
    /// Of the two, the one that started nearer the edge the tiles moved toward
    /// is the one the other slid into.
    public internal(set) var didMerge: Bool

    /// Creates a movement record, for example to describe an expected slide
    /// in a test or preview.
    public init(from: Position, to: Position, value: Int, didMerge: Bool) {
        self.from = from
        self.to = to
        self.value = value
        self.didMerge = didMerge
    }
}

/// A cell holding a tile that a slide created by merging two tiles.
public struct TileMerge: Hashable, Sendable {
    /// Where the merged tile is.
    public let position: Position
    /// The merged tile's value: twice the value of each tile that formed it.
    public let value: Int

    /// Creates a merge record, for example to describe an expected slide in a
    /// test or preview.
    public init(position: Position, value: Int) {
        self.position = position
        self.value = value
    }
}

/// The deterministic outcome of sliding a board in one direction, before a new
/// tile spawns.
///
/// Besides the new board it describes every tile's fate, which is enough to
/// animate the move: give each tile on the old board an identity, move the
/// tile at each movement's `from` to its `to`, then replace the two tiles that
/// arrive at each ``merges`` cell with one new tile of the merged value.
public struct SlideResult: Hashable, Sendable {
    /// The board after the slide.
    public let board: Board
    /// One entry for every tile on the board before the slide, including tiles
    /// that didn't move, ordered row-major by ``TileMovement/from``.
    public let movements: [TileMovement]
    /// The cells holding merged tiles after the slide, in row-major order.
    public let merges: [TileMerge]

    /// The points the slide scores: the sum of the merged tiles' values.
    public var scoreDelta: Int {
        merges.reduce(0) { $0 + $1.value }
    }

    /// Whether the slide left the board unchanged, in which case it doesn't
    /// count as a move.
    public var isNoOp: Bool {
        // A merge always moves at least one of its two tiles.
        movements.allSatisfy { $0.from == $0.to }
    }
}

extension Board {
    /// Slides every tile in `direction` as far as it can go, merging equal
    /// tiles that collide, as in the original 2048.
    ///
    /// Each line parallel to `direction` is processed from the edge the tiles
    /// move toward: a tile merges with the tile placed just before it if they
    /// have the same value and that tile isn't itself a merge result;
    /// otherwise it takes the next free cell. So a tile merges at most once per
    /// move, and with three or more equal tiles in a line the pair nearest the
    /// edge merges first: sliding the row `2 2 2 0` left gives `4 2 0 0`.
    ///
    /// This only slides; it doesn't spawn a tile.
    public func sliding(_ direction: Direction) -> SlideResult {
        var result = Board(size: size)
        var movements: [TileMovement] = []
        var merges: [TileMerge] = []
        movements.reserveCapacity(cells.count)
        for line in 0..<size {
            var nextOffset = 0
            // The cell index of the last tile placed on this line and the index
            // of its movement, while that tile can still take part in a merge.
            var mergeCandidate: (cell: Int, movement: Int)?
            for offset in 0..<size {
                let from = direction.position(line: line, offset: offset, size: size)
                let exponent = cells[index(of: from)]
                guard exponent != 0 else { continue }
                let value = Self.value(ofExponent: exponent)
                if let candidate = mergeCandidate, Self.canMerge(result.cells[candidate.cell], exponent) {
                    result.cells[candidate.cell] += 1
                    movements[candidate.movement].didMerge = true
                    let to = movements[candidate.movement].to
                    movements.append(TileMovement(from: from, to: to, value: value, didMerge: true))
                    merges.append(TileMerge(position: to, value: 2 * value))
                    mergeCandidate = nil
                } else {
                    let to = direction.position(line: line, offset: nextOffset, size: size)
                    nextOffset += 1
                    let cell = index(of: to)
                    result.cells[cell] = exponent
                    mergeCandidate = (cell, movements.count)
                    movements.append(TileMovement(from: from, to: to, value: value, didMerge: false))
                }
            }
        }
        movements.sort { isRowMajorOrdered($0.from, $1.from) }
        merges.sort { isRowMajorOrdered($0.position, $1.position) }
        return SlideResult(board: result, movements: movements, merges: merges)
    }
}

private func isRowMajorOrdered(_ first: Position, _ second: Position) -> Bool {
    (first.row, first.column) < (second.row, second.column)
}
