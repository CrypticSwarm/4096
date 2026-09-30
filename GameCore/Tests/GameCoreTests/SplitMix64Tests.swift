import Foundation
import GameCore
import Testing

struct SplitMix64Tests {
    static let referenceVectors: [(seed: UInt64, outputs: [UInt64])] = [
        (
            0,
            [
                0xE220_A839_7B1D_CDAF, 0x6E78_9E6A_A1B9_65F4, 0x06C4_5D18_8009_454F, 0xF88B_B8A8_724C_81EC,
                0x1B39_896A_51A8_749B,
            ]
        ),
        (
            1_234_567,
            [
                6_457_827_717_110_365_317, 3_203_168_211_198_807_973, 9_817_491_932_198_370_423,
                4_593_380_528_125_082_431, 16_408_922_859_458_223_821,
            ]
        ),
    ]

    /// Reference outputs of the published SplitMix64 algorithm.
    @Test(arguments: referenceVectors)
    func matchesReferenceVector(seed: UInt64, expected: [UInt64]) {
        var generator = SplitMix64(seed: seed)
        #expect(expected.map { _ in generator.next() } == expected)
    }

    @Test func sameSeedSameSequence() {
        var first = SplitMix64(seed: 42)
        var second = SplitMix64(seed: 42)
        #expect((0..<100).map { _ in first.next() } == (0..<100).map { _ in second.next() })
    }

    @Test func differentSeedsDiffer() {
        var first = SplitMix64(seed: 1)
        var second = SplitMix64(seed: 2)
        #expect((0..<10).map { _ in first.next() } != (0..<10).map { _ in second.next() })
    }

    /// Guards the persisted format: the state is the seed plus one increment
    /// per draw.
    @Test func decodesFromStableJSON() throws {
        let generator = try JSONDecoder().decode(SplitMix64.self, from: Data(#"{"state":7}"#.utf8))
        #expect(generator == SplitMix64(seed: 7))
    }

    @Test func codableRoundTripResumesSequence() throws {
        var generator = SplitMix64(seed: 7)
        _ = (0..<5).map { _ in generator.next() }
        var restored = try JSONDecoder().decode(SplitMix64.self, from: JSONEncoder().encode(generator))
        #expect(restored == generator)
        #expect((0..<10).map { _ in restored.next() } == (0..<10).map { _ in generator.next() })
    }
}
