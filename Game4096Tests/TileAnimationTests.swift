import GameCore
import Testing

@testable import Game4096

struct TileAnimationTests {
    @Test func resetShowsTheTilesAtOnce() throws {
        var layout = TileLayout(board: try Board(notation: "2,2;0,0"))
        layout.apply(
            try #require(
                Move(direction: .left, spawn: Spawn(position: Position(row: 1, column: 1), value: 2), on: layout.board))
        )
        layout.reset(to: try Board(notation: "0,4;2,0"))

        let steps = TileAnimation.steps(to: layout, reduceMotion: false)

        #expect(steps == [TileAnimation.Step(tiles: ShownTile.settled(layout.tiles), motion: .none, pause: 0)])
    }

    @Test func reduceMotionShowsAMoveAtOnce() throws {
        var layout = TileLayout(board: try Board(notation: "2,2;0,0"))
        layout.apply(
            try #require(
                Move(direction: .left, spawn: Spawn(position: Position(row: 1, column: 1), value: 2), on: layout.board))
        )

        let steps = TileAnimation.steps(to: layout, reduceMotion: true)

        #expect(steps == [TileAnimation.Step(tiles: ShownTile.settled(layout.tiles), motion: .none, pause: 0)])
    }

    @Test func moveSlidesThenPopsThenSettles() throws {
        // 2 2 4 left: the 2s merge into a 4 (id 3) at (0, 0), the 4 (id 2)
        // slides to (0, 1), and a 2 (id 4) spawns at (1, 2).
        var layout = TileLayout(board: try Board(notation: "2,2,4;0,0,0;0,0,0"))
        layout.apply(
            try #require(
                Move(direction: .left, spawn: Spawn(position: Position(row: 1, column: 2), value: 2), on: layout.board))
        )

        let steps = TileAnimation.steps(to: layout, reduceMotion: false)

        try #require(steps.count == 3)
        #expect(steps.map(\.motion) == [.slide, .pop, .none])
        #expect(steps[0].pause == Theme.Motion.slideDuration)
        #expect(steps[1].pause == Theme.Motion.popDuration)
        #expect(steps[0].tiles.map(\.tile) == layout.lastTransition?.slid)
        let slidTilesArePlain = steps[0].tiles.allSatisfy { $0 == ShownTile(tile: $0.tile) }
        #expect(slidTilesArePlain)

        let pop = Dictionary(uniqueKeysWithValues: steps[1].tiles.map { ($0.id, $0) })
        #expect(Set(pop.keys) == [0, 1, 2, 3, 4])
        #expect(pop[0]?.isMergedAway == true)
        #expect(pop[1]?.isMergedAway == true)
        #expect(pop[3]?.entrance == .pop)
        #expect(pop[4]?.entrance == .appear)
        #expect(pop[2]?.entrance == ShownTile.Entrance.none)
        // Merged-away tiles come first, so they are drawn underneath.
        let mergedAwayFirst = steps[1].tiles.prefix(2).allSatisfy(\.isMergedAway)
        #expect(mergedAwayFirst)

        #expect(steps[2].tiles == ShownTile.settled(layout.tiles))
    }

    /// Whatever step a newer layout interrupts, its steps have unique ids and
    /// end at its tiles, along whole seeded games.
    @Test(arguments: 3...5)
    func everyStepIsConsistent(size: Int) {
        let rules = GameRules(id: "\(size)", boardSize: size)
        var generator = SplitMix64(seed: 77)
        var layout = TileLayout(board: rules.startingBoard(using: &generator))
        for index in 0..<300 {
            let direction = Direction.allCases.randomElement(using: &generator)!
            if let move = rules.move(direction, on: layout.board, using: &generator) {
                layout.apply(move)
            } else if index % 5 == 0 {
                layout.reset(to: rules.startingBoard(using: &generator))
            }
            let steps = TileAnimation.steps(to: layout, reduceMotion: false)
            for step in steps {
                #expect(Set(step.tiles.map(\.id)).count == step.tiles.count)
            }
            #expect(steps.last?.tiles == ShownTile.settled(layout.tiles))
        }
    }
}

struct MoveAnnouncementTests {
    @Test func describesMergesAndSpawn() throws {
        var layout = TileLayout(board: try Board(notation: "2,2,4,4;0,0,0,0;0,0,0,0;0,0,0,0"))
        let transition = layout.apply(
            try #require(
                Move(direction: .left, spawn: Spawn(position: Position(row: 3, column: 1), value: 2), on: layout.board))
        )
        #expect(MoveAnnouncement.text(for: transition) == "Moved left. Made 4 and 8. New 2 in row 4, column 2.")
    }

    @Test func omitsMergesWhenThereAreNone() throws {
        var layout = TileLayout(board: try Board(notation: "2,0;0,0"))
        let transition = layout.apply(
            try #require(
                Move(direction: .down, spawn: Spawn(position: Position(row: 0, column: 1), value: 4), on: layout.board))
        )
        #expect(MoveAnnouncement.text(for: transition) == "Moved down. New 4 in row 1, column 2.")
        #expect(MoveAnnouncement.blockedText(for: .up) == "Can't move up.")
    }
}
