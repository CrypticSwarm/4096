/// A tile with an identity that persists while it slides, for animation.
///
/// ``Board`` stores only values; ``TileLayout`` gives each tile an ``id`` and
/// keeps it as the tile moves, so a view keyed by `id` can animate the tile
/// from its old cell to its new one.
public struct Tile: Identifiable, Hashable, Sendable {
    /// Unique among the tiles of one ``TileLayout``, including tiles it has
    /// removed: a new tile never reuses an old tile's id.
    public let id: Int
    /// The tile's value, a power of two.
    public let value: Int
    /// The cell the tile occupies.
    public let position: Position

    /// Creates a tile, for example to describe an expected layout in a test.
    public init(id: Int, value: Int, position: Position) {
        self.id = id
        self.value = value
        self.position = position
    }
}

/// The tiles of a board with stable identities, updated move by move.
///
/// ``apply(_:)`` follows a ``Move``: each tile keeps its id while it slides,
/// the two tiles of a merge are replaced by a new tile, and the spawned tile
/// gets a new id. It returns a ``TileTransition`` that describes the change
/// for animation, also kept as ``lastTransition``. Changes that aren't a
/// single move (a new game, undo, restoring a saved game) go through
/// ``reset(to:)``, which gives every tile a new id.
///
/// Ids come from a counter, so the same moves on the same board produce the
/// same ids.
public struct TileLayout: Hashable, Sendable {
    /// The tiles in row-major order of their positions.
    public private(set) var tiles: [Tile]
    /// The board the tiles show.
    public private(set) var board: Board
    /// How the last ``apply(_:)`` changed the tiles, or `nil` if the tiles
    /// were set by ``init(board:)`` or ``reset(to:)`` since. A view can
    /// animate the transition when it sees a new layout, or show the tiles
    /// directly when this is `nil`. A view that sees only some layouts (for
    /// example two changes within one update) may find ids in the transition
    /// that it never drew; it should still end at ``tiles``.
    public private(set) var lastTransition: TileTransition?
    /// The id the next new tile gets.
    private var nextID: Int

    /// Creates a layout of `board` with ids counting up from 0 in row-major
    /// order.
    public init(board: Board) {
        self.tiles = []
        self.board = board
        self.nextID = 0
        reset(to: board)
    }

    /// Replaces the tiles with those of `board`, all with new ids, in row-major
    /// order. Use it for any change that isn't animated as a move.
    public mutating func reset(to board: Board) {
        self.board = board
        lastTransition = nil
        tiles = board.positions.compactMap { position in
            board[position].map { makeTile(value: $0, at: position) }
        }
    }

    /// Follows `move`, which must have been played on ``board``, and returns
    /// how the tiles changed.
    ///
    /// - Precondition: `move.slide` starts from ``board``: its movements start
    ///   exactly at the positions and values of ``tiles``.
    @discardableResult
    public mutating func apply(_ move: Move) -> TileTransition {
        let movements = move.slide.movements
        // Both lists are row-major: tiles by position, movements by `from`.
        precondition(
            movements.map(\.from) == tiles.map(\.position) && movements.map(\.value) == tiles.map(\.value),
            "The move wasn't played on this layout's board")

        let slid = zip(tiles, movements).map { tile, movement in
            Tile(id: tile.id, value: tile.value, position: movement.to)
        }
        var tilesByPosition: [Position: Tile] = [:]
        for (tile, movement) in zip(slid, movements) where !movement.didMerge {
            tilesByPosition[tile.position] = tile
        }
        let merged = move.slide.merges.map { makeTile(value: $0.value, at: $0.position) }
        for tile in merged {
            tilesByPosition[tile.position] = tile
        }
        let spawned = makeTile(value: move.spawn.value, at: move.spawn.position)
        tilesByPosition[spawned.position] = spawned

        board = move.board
        tiles = board.positions.compactMap { tilesByPosition[$0] }
        let transition = TileTransition(direction: move.direction, slid: slid, merged: merged, spawned: spawned)
        lastTransition = transition
        return transition
    }

    private mutating func makeTile(value: Int, at position: Position) -> Tile {
        defer { nextID += 1 }
        return Tile(id: nextID, value: value, position: position)
    }
}

/// How the tiles of a ``TileLayout`` changed in one move, in the order to
/// animate it:
///
/// 1. Every tile slides: ``slid`` has each tile from before the move, with its
///    id and value, at its destination. The two tiles of a merge end up in the
///    same cell.
/// 2. Each pair of merged tiles is replaced by a tile of ``merged``, and the
///    ``spawned`` tile appears. The layout's tiles are now the result.
public struct TileTransition: Hashable, Sendable {
    /// The direction of the move.
    public let direction: Direction
    /// Every tile from before the move at the cell it slid to, in row-major
    /// order of where it started.
    public let slid: [Tile]
    /// The tiles created by merges, with new ids, in row-major order.
    public let merged: [Tile]
    /// The tile that spawned after the slide, with a new id.
    public let spawned: Tile

    /// The ids of the tiles that merged into the tiles of ``merged`` and are
    /// gone after the move.
    public var mergedAwayIDs: Set<Int> {
        let mergeCells = Set(merged.map(\.position))
        return Set(slid.filter { mergeCells.contains($0.position) }.map(\.id))
    }
}
