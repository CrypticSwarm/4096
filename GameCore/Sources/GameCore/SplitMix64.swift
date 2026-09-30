/// A small, fast, seedable pseudo-random number generator: SplitMix64
/// (Steele, Lea and Flood, 2014), as used to seed the xoshiro family.
///
/// The same seed yields the same sequence of `next()` values on every platform,
/// so games driven by it are reproducible in tests. Values derived through the
/// standard library (such as `Int.random(in:using:)`) are reproducible for a
/// given standard library. Not suitable for cryptography.
///
/// It is `Codable`, so a game can save the generator's state and resume the
/// same sequence.
public struct SplitMix64: RandomNumberGenerator, Hashable, Codable, Sendable {
    private var state: UInt64

    /// Creates a generator whose sequence is determined by `seed`.
    public init(seed: UInt64) {
        state = seed
    }

    /// Returns the next value in the sequence.
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
