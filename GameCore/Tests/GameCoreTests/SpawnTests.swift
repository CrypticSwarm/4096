import Foundation
import GameCore
import Testing

struct SpawnTests {
    @Test func spawnsOnlyInEmptyCells() {
        var generator = SplitMix64(seed: 3)
        for size in 2...6 {
            for _ in 0..<200 {
                let board = randomBoard(size: size, emptyChance: 0.3, using: &generator)
                guard let spawn = SpawnDistribution.classic.randomSpawn(on: board, using: &generator) else {
                    #expect(board.isFull)
                    continue
                }
                #expect(board.emptyPositions.contains(spawn.position))
                #expect([2, 4].contains(spawn.value))
                #expect(board.canPlace(spawn))
            }
        }
    }

    @Test(arguments: 2...6)
    func fullBoardGetsNoSpawnAndKeepsGeneratorUntouched(size: Int) {
        var generator = SplitMix64(seed: 5)
        let before = generator
        #expect(SpawnDistribution.classic.randomSpawn(on: stuckBoard(size: size), using: &generator) == nil)
        #expect(generator == before)
    }

    @Test func singleEmptyCellIsAlwaysChosen() throws {
        let board = try Board(rows: [[2, 4, 8], [16, 0, 32], [64, 128, 256]])
        var generator = SplitMix64(seed: 8)
        for _ in 0..<100 {
            #expect(
                SpawnDistribution.classic.randomSpawn(on: board, using: &generator)?.position
                    == Position(row: 1, column: 1))
        }
    }

    /// Loose bounds (about 5 standard deviations) on a fixed seed, so this is
    /// deterministic yet still catches a wrong distribution.
    @Test func classicDistributionIsNinetyTenAndPositionsUniform() {
        let draws = 20_000
        let board = Board(size: 4)
        var generator = SplitMix64(seed: 2048)
        var valueCounts: [Int: Int] = [:]
        var positionCounts: [Position: Int] = [:]
        for _ in 0..<draws {
            let spawn = SpawnDistribution.classic.randomSpawn(on: board, using: &generator)!
            valueCounts[spawn.value, default: 0] += 1
            positionCounts[spawn.position, default: 0] += 1
        }
        #expect(Set(valueCounts.keys) == [2, 4])
        #expect((1_800...2_200).contains(valueCounts[4, default: 0]))  // expected 2000, σ ≈ 42
        #expect(Set(positionCounts.keys) == Set(board.positions))
        for count in positionCounts.values {
            #expect((1_080...1_420).contains(count))  // expected 1250, σ ≈ 34
        }
    }

    /// Uniformity where the empty cells are scattered between tiles, which
    /// catches pickers biased by the board layout.
    @Test func positionsUniformOnPartlyFilledBoard() throws {
        let board = try Board(rows: [
            [2, 4, 8, 0],
            [0, 16, 32, 64],
            [2, 4, 0, 8],
            [16, 32, 64, 0],
        ])
        let draws = 10_000
        var generator = SplitMix64(seed: 404)
        var counts: [Position: Int] = [:]
        for _ in 0..<draws {
            counts[SpawnDistribution.classic.randomSpawn(on: board, using: &generator)!.position, default: 0] += 1
        }
        #expect(Set(counts.keys) == Set(board.emptyPositions))
        for count in counts.values {
            #expect((2_300...2_700).contains(count))  // expected 2500, σ ≈ 43
        }
    }

    @Test func customDistribution() {
        let onlyFours = SpawnDistribution(outcomes: [.init(value: 4, weight: 1)])
        let evenTwosAndEights = SpawnDistribution(outcomes: [.init(value: 2, weight: 5), .init(value: 8, weight: 5)])
        var generator = SplitMix64(seed: 12)
        var eights = 0
        for _ in 0..<2_000 {
            #expect(onlyFours.randomSpawn(on: Board(size: 5), using: &generator)?.value == 4)
            let value = evenTwosAndEights.randomSpawn(on: Board(size: 5), using: &generator)!.value
            #expect([2, 8].contains(value))
            eights += value == 8 ? 1 : 0
        }
        #expect((850...1_150).contains(eights))  // expected 1000, σ ≈ 22
    }

    @Test func threeOutcomeDistribution() {
        let distribution = SpawnDistribution(outcomes: [
            .init(value: 2, weight: 1), .init(value: 4, weight: 2), .init(value: 8, weight: 7),
        ])
        var generator = SplitMix64(seed: 13)
        var counts: [Int: Int] = [:]
        for _ in 0..<10_000 {
            counts[distribution.randomSpawn(on: Board(size: 3), using: &generator)!.value, default: 0] += 1
        }
        #expect(Set(counts.keys) == [2, 4, 8])
        #expect((850...1_150).contains(counts[2, default: 0]))  // expected 1000, σ = 30
        #expect((1_800...2_200).contains(counts[4, default: 0]))  // expected 2000, σ = 40
        #expect((6_770...7_230).contains(counts[8, default: 0]))  // expected 7000, σ ≈ 46
    }

    @Test func sameSeedSameSpawns() {
        func spawns(seed: UInt64) -> [Spawn] {
            var generator = SplitMix64(seed: seed)
            var board = Board(size: 4)
            var result: [Spawn] = []
            while let spawn = SpawnDistribution.classic.randomSpawn(on: board, using: &generator) {
                result.append(spawn)
                board = board.placing(spawn)
            }
            return result
        }
        #expect(spawns(seed: 77) == spawns(seed: 77))
        #expect(spawns(seed: 77).count == 16)
        #expect(spawns(seed: 77) != spawns(seed: 78))
    }

    @Test func placingAddsTheTile() throws {
        let board = try Board(rows: [[2, 0], [0, 0]])
        let placed = board.placing(Spawn(position: Position(row: 1, column: 0), value: 4))
        #expect(placed.rows == [[2, 0], [4, 0]])
        #expect(board.rows == [[2, 0], [0, 0]])
    }

    @Test(arguments: [
        Spawn(position: Position(row: 0, column: 0), value: 2),  // occupied
        Spawn(position: Position(row: 2, column: 0), value: 2),  // off the board
        Spawn(position: Position(row: 0, column: -1), value: 2),  // off the board
        Spawn(position: Position(row: 1, column: 1), value: 3),  // not a power of two
        Spawn(position: Position(row: 1, column: 1), value: 0),
        Spawn(position: Position(row: 1, column: 1), value: 1),
    ])
    func cannotPlaceInvalidSpawns(spawn: Spawn) throws {
        #expect(!(try Board(rows: [[2, 0], [0, 0]]).canPlace(spawn)))
    }

    @Test func spawnCodableRoundTrip() throws {
        let spawn = Spawn(position: Position(row: 2, column: 3), value: 4)
        #expect(try JSONDecoder().decode(Spawn.self, from: JSONEncoder().encode(spawn)) == spawn)
    }

    /// Guards the persisted format of spawns, which sessions record for redo.
    @Test func spawnDecodesFromStableJSON() throws {
        let json = #"{"position":{"row":2,"column":3},"value":4}"#
        #expect(
            try JSONDecoder().decode(Spawn.self, from: Data(json.utf8))
                == Spawn(position: Position(row: 2, column: 3), value: 4))
    }

    @Test func distributionCodableRoundTrip() throws {
        let custom = SpawnDistribution(outcomes: [.init(value: 2, weight: 3), .init(value: 1 << 10, weight: 1)])
        for distribution in [SpawnDistribution.classic, custom] {
            let data = try JSONEncoder().encode(distribution)
            #expect(try JSONDecoder().decode(SpawnDistribution.self, from: data) == distribution)
        }
    }

    @Test(arguments: [
        #"{"outcomes":[]}"#,
        #"{"outcomes":[{"value":3,"weight":1}]}"#,
        #"{"outcomes":[{"value":1,"weight":1}]}"#,
        #"{"outcomes":[{"value":2,"weight":0}]}"#,
        #"{"outcomes":[{"value":2,"weight":-1}]}"#,
        #"{"outcomes":[{"value":2,"weight":9223372036854775807},{"value":4,"weight":1}]}"#,
    ])
    func decodingRejectsInvalidDistributions(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SpawnDistribution.self, from: Data(json.utf8))
        }
    }
}
