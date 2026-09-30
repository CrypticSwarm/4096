/// A game in progress: the board and score under a variant's rules, plus
/// everything needed to continue it exactly, including its random number
/// generator.
///
/// A session is a value: every action is a `mutating` method, and copies are
/// independent games. Given the same seed and the same actions, a session
/// always ends up in the same state, which makes games reproducible in tests.
///
/// ## High score
///
/// ``highScore`` is the best score reached in the session's variant, including
/// earlier games: pass the stored best to the initializer and the session
/// raises it whenever the score beats it. Nothing lowers it, and ``restart()``
/// keeps it, so code that shows the session never updates the high score
/// itself.
public struct GameSession: Hashable, Sendable {
    /// The variant being played.
    public let rules: GameRules
    /// The current board.
    public private(set) var board: Board
    /// The current score: the sum of the values of all tiles merged so far.
    public private(set) var score: Int
    /// The best score reached in this variant, in this game or an earlier one.
    /// Always at least ``score``.
    public private(set) var highScore: Int

    /// Draws the starting tiles and the tile each move spawns.
    private var generator: SplitMix64

    /// Starts a new game: the board gets the rules' starting tiles, drawn from
    /// a generator seeded with `seed`.
    ///
    /// - Parameters:
    ///   - rules: The variant to play.
    ///   - seed: Determines the whole game, given the same actions.
    ///   - highScore: The best score reached in this variant so far.
    /// - Precondition: `highScore` isn't negative.
    public init(rules: GameRules, seed: UInt64, highScore: Int = 0) {
        precondition(highScore >= 0, "A high score can't be negative")
        var generator = SplitMix64(seed: seed)
        self.rules = rules
        self.board = rules.startingBoard(using: &generator)
        self.score = 0
        self.highScore = highScore
        self.generator = generator
    }

    /// Starts a game on a given board, for example to set up a test or a
    /// preview close to a win or to game over.
    ///
    /// - Parameters:
    ///   - rules: The variant to play.
    ///   - board: The board to play on.
    ///   - score: The score so far.
    ///   - seed: Seeds the generator that draws the tiles moves spawn.
    ///   - highScore: The best score reached in this variant so far; the
    ///     session's high score is the larger of this and `score`.
    /// - Precondition: `rules` accept `board`, and neither score is negative.
    public init(rules: GameRules, board: Board, score: Int = 0, seed: UInt64, highScore: Int = 0) {
        precondition(rules.accepts(board), "A \(board.size)×\(board.size) board doesn't fit rules \"\(rules.id)\"")
        precondition(score >= 0 && highScore >= 0, "Scores can't be negative")
        self.rules = rules
        self.board = board
        self.score = score
        self.highScore = max(highScore, score)
        self.generator = SplitMix64(seed: seed)
    }

    /// Whether the game is over: no swipe changes the board. Undo may still
    /// be available.
    public var isGameOver: Bool {
        !board.hasAvailableMoves
    }

    /// Plays a swipe: slides the board in `direction`, spawns a new tile and
    /// adds the points scored.
    ///
    /// - Returns: The move, whose ``Move/slide`` and ``Move/spawn`` describe
    ///   how to animate it, or `nil` if the swipe doesn't change the board. Such
    ///   a swipe is ignored: the session is left exactly as it was.
    @discardableResult
    public mutating func move(_ direction: Direction) -> Move? {
        guard let move = rules.move(direction, on: board, using: &generator) else { return nil }
        apply(move)
        return move
    }

    /// Starts a new game in the same variant with new starting tiles and a
    /// score of 0. The high score is kept.
    public mutating func restart() {
        board = rules.startingBoard(using: &generator)
        score = 0
    }

    /// Makes `move`, which was played on the current board, the current state.
    private mutating func apply(_ move: Move) {
        board = move.board
        score = Self.adding(move.scoreDelta, to: score)
        highScore = max(highScore, score)
    }

    /// Adds points to a score, stopping at `Int.max` rather than trapping, so
    /// a tampered saved score can't crash the game.
    static func adding(_ points: Int, to score: Int) -> Int {
        let (sum, overflow) = score.addingReportingOverflow(points)
        return overflow ? .max : sum
    }
}
