import GameCore

/// A tile as drawn during an animation.
struct ShownTile: Identifiable, Equatable {
    /// How a tile appears when it is inserted.
    enum Entrance: Equatable {
        /// Instantly: tiles that were already there, or a whole new board.
        case none
        /// Grows and overshoots: a tile made by a merge.
        case pop
        /// Grows and fades in: a spawned tile.
        case appear
    }

    var tile: Tile
    var entrance = Entrance.none
    /// Whether the tile merged into another and is drawn below it until the
    /// merged tile has popped.
    var isMergedAway = false

    var id: Int { tile.id }

    /// The tiles, drawn plainly.
    static func settled(_ tiles: [Tile]) -> [ShownTile] {
        tiles.map { ShownTile(tile: $0) }
    }
}

/// The steps that take the drawn tiles to a new ``TileLayout``, timed like
/// the original game. A board view shows each step's tiles with its motion,
/// then waits its pause. The last step always shows exactly the layout's
/// tiles, so a view that is interrupted by a newer layout and starts over
/// with that layout's steps still ends up in sync.
enum TileAnimation {
    /// One state of the drawn tiles.
    struct Step: Equatable {
        /// How the change to this step's tiles animates.
        enum Motion: Equatable {
            /// No animation.
            case none
            /// Tiles slide to their new cells.
            case slide
            /// New tiles pop or appear.
            case pop
        }

        var tiles: [ShownTile]
        var motion: Motion
        /// Seconds to wait before the next step.
        var pause: Double
    }

    /// The steps to show `layout`: slide, then merge and spawn, then settle
    /// if it was reached by a move; otherwise (a reset, or with Reduce Motion)
    /// its tiles at once.
    static func steps(to layout: TileLayout, reduceMotion: Bool) -> [Step] {
        let settled = Step(tiles: ShownTile.settled(layout.tiles), motion: .none, pause: 0)
        guard let transition = layout.lastTransition, !reduceMotion else { return [settled] }

        // 1. Every tile slides to its destination; merging pairs meet.
        let slide = Step(tiles: ShownTile.settled(transition.slid), motion: .slide, pause: Theme.Motion.slideDuration)

        // 2. Merged tiles pop over the pairs they replace, and the new tile
        //    appears.
        let mergedAway = transition.mergedAwayIDs
        let mergedIDs = Set(transition.merged.map(\.id))
        let underneath = transition.slid.filter { mergedAway.contains($0.id) }.map {
            ShownTile(tile: $0, isMergedAway: true)
        }
        let result = layout.tiles.map { tile in
            let entrance: ShownTile.Entrance =
                if mergedIDs.contains(tile.id) {
                    .pop
                } else if tile.id == transition.spawned.id {
                    .appear
                } else {
                    .none
                }
            return ShownTile(tile: tile, entrance: entrance)
        }
        let pop = Step(tiles: underneath + result, motion: .pop, pause: Theme.Motion.popDuration)

        // 3. The merged-away tiles, now covered, go.
        return [slide, pop, settled]
    }
}
