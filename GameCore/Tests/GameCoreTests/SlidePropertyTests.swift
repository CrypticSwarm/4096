import GameCore
import Testing

/// Invariants of `Board.sliding(_:)` over many seeded random boards.
struct SlidePropertyTests {
    static let boardsPerSize = 200

    @Test(arguments: 2...6)
    func invariantsHold(size: Int) {
        var generator = SplitMix64(seed: 1_000 + UInt64(size))
        for _ in 0..<Self.boardsPerSize {
            let emptyChance = Double.random(in: 0...0.8, using: &generator)
            let board = randomBoard(size: size, emptyChance: emptyChance, using: &generator)
            for direction in Direction.allCases {
                checkInvariants(of: board.sliding(direction), from: board, toward: direction)
            }
        }
    }

    @Test(arguments: 3...5)
    func invariantsHoldAlongPlayedGames(size: Int) {
        // Boards reached in play rather than uniformly random ones.
        let rules = GameRules(id: "\(size)", boardSize: size)
        var generator = SplitMix64(seed: 99 + UInt64(size))
        for _ in 0..<5 {
            var board = rules.startingBoard(using: &generator)
            while board.hasAvailableMoves {
                for direction in Direction.allCases {
                    checkInvariants(of: board.sliding(direction), from: board, toward: direction)
                }
                let direction = Direction.allCases.randomElement(using: &generator)!
                board = rules.move(direction, on: board, using: &generator)?.board ?? board
            }
        }
    }

    /// Checks everything that must hold for `result = board.sliding(direction)`.
    private func checkInvariants(
        of result: SlideResult, from board: Board, toward direction: Direction,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let after = result.board
        let context = Comment(rawValue: "\(direction) on\n\(board)\ngave\n\(after)")

        // Agreement with the reference model on independently extracted lines.
        let reference = lines(of: board.rows, toward: direction).map(referenceSlide)
        #expect(
            after.rows == rows(fromLines: reference.map(\.row), toward: direction), context,
            sourceLocation: sourceLocation)
        #expect(result.scoreDelta == reference.map(\.score).reduce(0, +), context, sourceLocation: sourceLocation)

        // Conservation.
        #expect(after.size == board.size, context, sourceLocation: sourceLocation)
        #expect(after.tileSum == board.tileSum, context, sourceLocation: sourceLocation)
        #expect(after.tileCount == board.tileCount - result.merges.count, context, sourceLocation: sourceLocation)

        // No-op detection.
        #expect(result.isNoOp == (after == board), context, sourceLocation: sourceLocation)
        if result.isNoOp {
            #expect(result.merges.isEmpty, context, sourceLocation: sourceLocation)
        } else {
            // A real move always frees a cell, so there is room to spawn.
            #expect(!after.isFull, context, sourceLocation: sourceLocation)
        }
        if board.tileCount > 0 {  // On an empty board nothing can slide, but the game isn't over.
            #expect(
                board.hasAvailableMoves == Direction.allCases.contains { !board.sliding($0).isNoOp }, context,
                sourceLocation: sourceLocation)
        }

        // One movement per original tile, in row-major order, with its value.
        #expect(result.movements.map(\.from) == board.tilePositions, context, sourceLocation: sourceLocation)
        for movement in result.movements {
            #expect(board[movement.from] == movement.value, context, sourceLocation: sourceLocation)
        }

        // Replaying the movements on the old board reproduces the new board.
        let arrivals = Dictionary(grouping: result.movements, by: \.to)
        #expect(Set(arrivals.keys) == Set(after.tilePositions), context, sourceLocation: sourceLocation)
        var expectedMerges: [TileMerge] = []
        for (destination, incoming) in arrivals {
            switch incoming.count {
            case 1:
                #expect(!incoming[0].didMerge, context, sourceLocation: sourceLocation)
                #expect(after[destination] == incoming[0].value, context, sourceLocation: sourceLocation)
            case 2:
                #expect(incoming.allSatisfy { $0.didMerge }, context, sourceLocation: sourceLocation)
                #expect(incoming[0].value == incoming[1].value, context, sourceLocation: sourceLocation)
                #expect(after[destination] == 2 * incoming[0].value, context, sourceLocation: sourceLocation)
                expectedMerges.append(TileMerge(position: destination, value: 2 * incoming[0].value))
            default:
                Issue.record(
                    "\(incoming.count) tiles arrived at \(destination). \(context)", sourceLocation: sourceLocation)
            }
        }
        #expect(Set(result.merges) == Set(expectedMerges), context, sourceLocation: sourceLocation)
        #expect(
            result.merges.map(\.position)
                == after.tilePositions.filter { p in result.merges.contains { $0.position == p } },
            "merges are row-major", sourceLocation: sourceLocation)

        // Tiles move straight toward the edge and never pass each other.
        for movement in result.movements {
            #expect(
                line(of: movement.from, direction) == line(of: movement.to, direction), context,
                sourceLocation: sourceLocation)
            #expect(
                offset(of: movement.to, direction, size: board.size)
                    <= offset(of: movement.from, direction, size: board.size),
                context, sourceLocation: sourceLocation)
        }
        for first in result.movements {
            for second in result.movements
            where line(of: first.from, direction) == line(of: second.from, direction)
                && offset(of: first.from, direction, size: board.size)
                    < offset(of: second.from, direction, size: board.size)
            {
                #expect(
                    offset(of: first.to, direction, size: board.size)
                        <= offset(of: second.to, direction, size: board.size),
                    context, sourceLocation: sourceLocation)
            }
        }
    }

    // Line geometry, restated from the definition of each direction.

    private func line(of position: Position, _ direction: Direction) -> Int {
        direction == .left || direction == .right ? position.row : position.column
    }

    private func offset(of position: Position, _ direction: Direction, size: Int) -> Int {
        switch direction {
        case .left: position.column
        case .right: size - 1 - position.column
        case .up: position.row
        case .down: size - 1 - position.row
        }
    }
}
