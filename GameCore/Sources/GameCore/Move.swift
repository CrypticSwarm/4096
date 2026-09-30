/// A completed move: a slide that changed the board, followed by one new tile.
///
/// ``direction`` and ``spawn`` are all it takes to record a move:
/// ``init(direction:spawn:on:)`` replays it exactly on the board it was
/// played on, which is how redo works. ``slide`` carries the tile movements
/// for animation.
public struct Move: Hashable, Sendable {
    /// The direction the tiles slid.
    public let direction: Direction
    /// The slide, with the board before the spawn and how each tile moved.
    public let slide: SlideResult
    /// The tile that appeared after the slide.
    public let spawn: Spawn
    /// The board after the move, including the spawned tile.
    public let board: Board

    /// The points the move scores: the sum of the values of merged tiles.
    public var scoreDelta: Int {
        slide.scoreDelta
    }

    /// Replays a recorded move on `board`: slides it in `direction` and places
    /// `spawn`, with no randomness.
    ///
    /// Returns `nil` if the slide doesn't change `board` or `spawn` can't be
    /// placed on the slid board (see ``Board/canPlace(_:)``), so a record that
    /// doesn't belong to `board` is rejected rather than trapping.
    public init?(direction: Direction, spawn: Spawn, on board: Board) {
        let slide = board.sliding(direction)
        guard !slide.isNoOp, slide.board.canPlace(spawn) else { return nil }
        self.init(direction: direction, slide: slide, spawn: spawn)
    }

    init(direction: Direction, slide: SlideResult, spawn: Spawn) {
        self.direction = direction
        self.slide = slide
        self.spawn = spawn
        self.board = slide.board.placing(spawn)
    }
}
