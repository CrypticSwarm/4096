/// A tile that appears on the board, after a move or at the start of a game.
///
/// Sliding is deterministic, so a move's direction together with its spawn
/// reproduces the move exactly (see ``Move/init(direction:spawn:on:)``).
public struct Spawn: Hashable, Codable, Sendable {
    /// Where the tile appears.
    public var position: Position
    /// The tile's value.
    public var value: Int

    /// Creates a spawn of a tile with `value` at `position`.
    public init(position: Position, value: Int) {
        self.position = position
        self.value = value
    }
}

extension Board {
    /// Whether `spawn` can be placed: its position is an empty cell on the
    /// board and its value is a valid tile value.
    public func canPlace(_ spawn: Spawn) -> Bool {
        contains(spawn.position) && self[spawn.position] == nil && Self.exponent(ofTileValue: spawn.value) != nil
    }

    /// Returns the board with the spawned tile added.
    ///
    /// - Precondition: ``canPlace(_:)`` is `true` for `spawn`.
    public func placing(_ spawn: Spawn) -> Board {
        precondition(canPlace(spawn), "Can't place a \(spawn.value) at \(spawn.position) on\n\(self)")
        var board = self
        board.cells[index(of: spawn.position)] = Self.exponent(ofTileValue: spawn.value)!
        return board
    }
}

/// The values a new tile can have and how likely each is.
///
/// Probabilities are integer weights, so they are exact and persist without
/// rounding: the classic 90% 2s and 10% 4s is weights 9 and 1.
public struct SpawnDistribution: Hashable, Codable, Sendable {
    /// One possible value of a new tile and its relative weight.
    public struct Outcome: Hashable, Codable, Sendable {
        /// The tile value.
        public let value: Int
        /// The relative likelihood of this value: its probability is this
        /// weight divided by the sum of all weights.
        public let weight: Int

        /// Creates an outcome of `value` with the relative likelihood `weight`.
        public init(value: Int, weight: Int) {
            self.value = value
            self.weight = weight
        }
    }

    /// The possible outcomes.
    public let outcomes: [Outcome]

    /// The original game's distribution: a 2 with probability 0.9, a 4 with 0.1.
    public static let classic = SpawnDistribution([
        Outcome(value: 2, weight: 9),
        Outcome(value: 4, weight: 1),
    ])

    /// Creates a distribution from its outcomes.
    ///
    /// - Precondition: There is at least one outcome, every value is a valid
    ///   tile value (a power of two from 2 through ``Board/maxTileValue``),
    ///   every weight is positive, and the weights' sum fits in an `Int`.
    public init(_ outcomes: [Outcome]) {
        if let problem = Self.problem(with: outcomes) {
            preconditionFailure(problem)
        }
        self.outcomes = outcomes
    }

    /// Decodes a distribution, rejecting outcomes that ``init(_:)`` would.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let outcomes = try container.decode([Outcome].self, forKey: .outcomes)
        if let problem = Self.problem(with: outcomes) {
            throw DecodingError.dataCorruptedError(forKey: .outcomes, in: container, debugDescription: problem)
        }
        self.outcomes = outcomes
    }

    /// Picks a random spawn for `board`: a uniformly random empty cell (from
    /// ``Board/emptyPositions``), then a value from this distribution.
    ///
    /// - Returns: The spawn, or `nil` without using `generator` if the board is
    ///   full.
    public func randomSpawn(on board: Board, using generator: inout some RandomNumberGenerator) -> Spawn? {
        guard let position = board.emptyPositions.randomElement(using: &generator) else { return nil }
        return Spawn(position: position, value: randomValue(using: &generator))
    }

    private func randomValue(using generator: inout some RandomNumberGenerator) -> Int {
        let totalWeight = outcomes.reduce(0) { $0 + $1.weight }
        var roll = Int.random(in: 0..<totalWeight, using: &generator)
        for outcome in outcomes {
            if roll < outcome.weight {
                return outcome.value
            }
            roll -= outcome.weight
        }
        preconditionFailure("The roll is always below the total weight")
    }

    private static func problem(with outcomes: [Outcome]) -> String? {
        guard !outcomes.isEmpty else { return "A spawn distribution needs at least one outcome" }
        var totalWeight = 0
        for outcome in outcomes {
            guard Board.exponent(ofTileValue: outcome.value) != nil else {
                return "\(outcome.value) is not a valid tile value"
            }
            guard outcome.weight > 0 else { return "Weight \(outcome.weight) of \(outcome.value) is not positive" }
            let (sum, overflow) = totalWeight.addingReportingOverflow(outcome.weight)
            guard !overflow else { return "The weights' sum overflows" }
            totalWeight = sum
        }
        return nil
    }
}
