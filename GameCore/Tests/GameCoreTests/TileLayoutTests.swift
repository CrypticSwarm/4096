import GameCore
import Testing

struct TileLayoutTests {
    @Test func initNumbersTilesRowMajor() throws {
        let board = try Board(rows: [[0, 2, 0], [4, 0, 8], [0, 0, 2]])
        let layout = TileLayout(board: board)
        #expect(
            layout.tiles == [
                Tile(id: 0, value: 2, position: at(0, 1)),
                Tile(id: 1, value: 4, position: at(1, 0)),
                Tile(id: 2, value: 8, position: at(1, 2)),
                Tile(id: 3, value: 2, position: at(2, 2)),
            ])
        #expect(layout.board == board)
        #expect(layout.lastTransition == nil)
        #expect(TileLayout(board: Board(size: 4)).tiles.isEmpty)
    }

    @Test func applyKeepsIdsOfSlidingTilesAndNumbersNewOnes() throws {
        // Row 0: the 2s merge at column 0 and the 4 slides next to them.
        // Row 1: the 8 stays put. Row 2: the 2 slides to column 0.
        let board = try Board(rows: [[2, 2, 4], [8, 0, 0], [0, 0, 2]])
        var layout = TileLayout(board: board)
        let move = try #require(Move(direction: .left, spawn: Spawn(position: at(2, 2), value: 4), on: board))

        let transition = layout.apply(move)

        #expect(transition.direction == .left)
        #expect(
            transition.slid == [
                Tile(id: 0, value: 2, position: at(0, 0)),
                Tile(id: 1, value: 2, position: at(0, 0)),
                Tile(id: 2, value: 4, position: at(0, 1)),
                Tile(id: 3, value: 8, position: at(1, 0)),
                Tile(id: 4, value: 2, position: at(2, 0)),
            ])
        #expect(transition.merged == [Tile(id: 5, value: 4, position: at(0, 0))])
        #expect(transition.spawned == Tile(id: 6, value: 4, position: at(2, 2)))
        #expect(transition.mergedAwayIDs == [0, 1])
        #expect(
            layout.tiles == [
                Tile(id: 5, value: 4, position: at(0, 0)),
                Tile(id: 2, value: 4, position: at(0, 1)),
                Tile(id: 3, value: 8, position: at(1, 0)),
                Tile(id: 4, value: 2, position: at(2, 0)),
                Tile(id: 6, value: 4, position: at(2, 2)),
            ])
        #expect(layout.board == move.board)
        #expect(layout.lastTransition == transition)
    }

    @Test func mergedTileKeepsNoIdOfItsSources() throws {
        // [2, 2, 2, 2] right: two merges, each a new tile.
        let board = try Board(rows: [[2, 2, 2, 2], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        var layout = TileLayout(board: board)
        let move = try #require(Move(direction: .right, spawn: Spawn(position: at(3, 3), value: 2), on: board))

        let transition = layout.apply(move)

        #expect(transition.slid.map(\.position) == [at(0, 2), at(0, 2), at(0, 3), at(0, 3)])
        #expect(
            transition.merged == [Tile(id: 4, value: 4, position: at(0, 2)), Tile(id: 5, value: 4, position: at(0, 3))])
        #expect(transition.mergedAwayIDs == [0, 1, 2, 3])
        #expect(layout.tiles.map(\.id) == [4, 5, 6])
    }

    @Test func resetGivesEveryTileANewIdAndNoTransition() throws {
        let board = try Board(rows: [[2, 0], [0, 4]])
        var layout = TileLayout(board: board)

        layout.apply(try #require(Move(direction: .up, spawn: Spawn(position: at(1, 1), value: 2), on: board)))
        #expect(layout.lastTransition != nil)
        layout.reset(to: board)

        #expect(layout.lastTransition == nil)
        #expect(layout.tiles == [Tile(id: 3, value: 2, position: at(0, 0)), Tile(id: 4, value: 4, position: at(1, 1))])
        #expect(layout.board == board)

        layout.reset(to: Board(size: 3))
        #expect(layout.tiles.isEmpty)
        #expect(layout.board == Board(size: 3))
    }

    @Test func sameMovesGiveSameIds() {
        func play() -> [TileLayout] {
            var generator = SplitMix64(seed: 7)
            var layout = TileLayout(board: GameRules.classic.startingBoard(using: &generator))
            var history = [layout]
            for index in 0..<50 {
                if let move = GameRules.classic.move(Direction.allCases[index % 4], on: layout.board, using: &generator)
                {
                    layout.apply(move)
                    history.append(layout)
                }
            }
            return history
        }
        #expect(play() == play())
    }

    /// Follows whole seeded games of several sizes and checks every transition
    /// against the engine's board and slide.
    @Test(arguments: 2...6)
    func layoutTracksPlayedGames(size: Int) {
        let rules = GameRules(id: "\(size)", boardSize: size)
        var generator = SplitMix64(seed: 500 + UInt64(size))
        for _ in 0..<10 {
            var layout = TileLayout(board: rules.startingBoard(using: &generator))
            var seenIDs = Set(layout.tiles.map(\.id))
            checkMatches(layout, layout.board)
            var moves = 0
            while layout.board.hasAvailableMoves && moves < 2_000 {
                let direction = Direction.allCases.randomElement(using: &generator)!
                guard let move = rules.move(direction, on: layout.board, using: &generator) else { continue }
                let before = layout
                let transition = layout.apply(move)
                moves += 1

                checkMatches(layout, move.board)
                check(transition, of: move, from: before, to: layout, seenIDs: seenIDs)
                #expect(layout.lastTransition == transition)
                seenIDs.formUnion(layout.tiles.map(\.id))

                if moves % 97 == 0 {
                    // Resets in mid-game, as after an undo, renumber every tile.
                    let previous = seenIDs
                    layout.reset(to: layout.board)
                    checkMatches(layout, move.board)
                    #expect(layout.lastTransition == nil)
                    #expect(previous.isDisjoint(with: layout.tiles.map(\.id)))
                    seenIDs.formUnion(layout.tiles.map(\.id))
                }
            }
        }
    }

    /// The layout's tiles are exactly the board's tiles, row-major, with unique ids.
    private func checkMatches(
        _ layout: TileLayout, _ board: Board, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(layout.board == board, sourceLocation: sourceLocation)
        #expect(layout.tiles.map(\.position) == board.tilePositions, sourceLocation: sourceLocation)
        #expect(layout.tiles.allSatisfy { board[$0.position] == $0.value }, sourceLocation: sourceLocation)
        #expect(Set(layout.tiles.map(\.id)).count == layout.tiles.count, sourceLocation: sourceLocation)
    }

    private func check(
        _ transition: TileTransition, of move: Move, from before: TileLayout, to after: TileLayout,
        seenIDs: Set<Int>, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let context = Comment(rawValue: "\(move.direction) on\n\(before.board)")
        #expect(transition.direction == move.direction, context, sourceLocation: sourceLocation)

        // Every old tile slides with its id and value to its movement's destination.
        #expect(transition.slid.map(\.id) == before.tiles.map(\.id), context, sourceLocation: sourceLocation)
        #expect(transition.slid.map(\.value) == before.tiles.map(\.value), context, sourceLocation: sourceLocation)
        #expect(
            transition.slid.map(\.position) == move.slide.movements.map(\.to), context, sourceLocation: sourceLocation)

        // New tiles have ids never seen before, and match the engine's merges and spawn.
        let newTiles = transition.merged + [transition.spawned]
        #expect(seenIDs.isDisjoint(with: newTiles.map(\.id)), context, sourceLocation: sourceLocation)
        #expect(
            transition.merged.map { TileMerge(position: $0.position, value: $0.value) } == move.slide.merges, context,
            sourceLocation: sourceLocation)
        #expect(
            Spawn(position: transition.spawned.position, value: transition.spawned.value) == move.spawn, context,
            sourceLocation: sourceLocation)

        // The merged-away tiles are the two sources of each merge, and are gone.
        let movementByID = Dictionary(zip(before.tiles.map(\.id), move.slide.movements)) { first, _ in first }
        #expect(
            transition.mergedAwayIDs == Set(movementByID.filter { $0.value.didMerge }.keys), context,
            sourceLocation: sourceLocation)
        #expect(transition.mergedAwayIDs.count == 2 * transition.merged.count, context, sourceLocation: sourceLocation)

        // Afterwards: the surviving slid tiles, the merged tiles and the spawn.
        let survivors = transition.slid.filter { !transition.mergedAwayIDs.contains($0.id) }
        #expect(Set(after.tiles) == Set(survivors + newTiles), context, sourceLocation: sourceLocation)
    }
}
