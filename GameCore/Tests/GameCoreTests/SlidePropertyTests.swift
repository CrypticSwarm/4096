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

    @Test func invariantsHoldAlongPlayedGames() {
        // Boards reached in play (with spawns) rather than uniformly random ones.
        var generator = SplitMix64(seed: 99)
        for size in 3...5 {
            var board = Board(size: size)
            for _ in 0..<500 {
                if let empty = board.emptyPositions.randomElement(using: &generator) {
                    var rows = board.rows
                    rows[empty.row][empty.column] = Int.random(in: 0..<10, using: &generator) == 0 ? 4 : 2
                    board = try! Board(rows: rows)
                }
                let direction = Direction.allCases.randomElement(using: &generator)!
                let result = board.sliding(direction)
                checkInvariants(of: result, from: board, toward: direction)
                if !board.hasAvailableMoves { break }
                board = result.board
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

        // Conservation and scoring.
        #expect(after.size == board.size, context, sourceLocation: sourceLocation)
        #expect(after.tileSum == board.tileSum, context, sourceLocation: sourceLocation)
        #expect(result.scoreDelta == result.merges.map(\.value).reduce(0, +), context, sourceLocation: sourceLocation)
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
                #expect(!incoming[0].merged, context, sourceLocation: sourceLocation)
                #expect(after[destination] == incoming[0].value, context, sourceLocation: sourceLocation)
            case 2:
                #expect(incoming.allSatisfy { $0.merged }, context, sourceLocation: sourceLocation)
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

        // Each line of the result is packed against the edge, and any two
        // neighbors in a line with equal values include a merge result (two
        // original tiles that meet always merge).
        let mergedPositions = Set(result.merges.map(\.position))
        for (lineIndex, values) in lines(of: after.rows, toward: direction).enumerated() {
            let tileCount = values.count { $0 != 0 }
            #expect(values.prefix(tileCount).allSatisfy { $0 != 0 }, context, sourceLocation: sourceLocation)
            for offset in 0..<max(0, tileCount - 1)
            where values[offset] == values[offset + 1] && values[offset] < Board.maxTileValue {
                let pair = [offset, offset + 1].map {
                    position(line: lineIndex, offset: $0, direction, size: board.size)
                }
                #expect(pair.contains(where: mergedPositions.contains), context, sourceLocation: sourceLocation)
            }
        }
    }

    // Line geometry, written independently of the engine's own mapping.

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

    private func position(line: Int, offset: Int, _ direction: Direction, size: Int) -> Position {
        switch direction {
        case .left: Position(row: line, column: offset)
        case .right: Position(row: line, column: size - 1 - offset)
        case .up: Position(row: offset, column: line)
        case .down: Position(row: size - 1 - offset, column: line)
        }
    }
}
