/// A game in progress: the board and score under a variant's rules, plus
/// everything needed to continue it exactly, including its random number
/// generator.
///
/// A session is a value: every action is a `mutating` method, and copies are
/// independent games. Given the same seed and the same actions, a session
/// always ends up in the same state, which makes games reproducible in tests.
///
/// ## Undo and redo
///
/// The session remembers the last ``undoLimit`` moves. ``undo()`` takes back
/// the most recent one and ``redo()`` plays it again exactly, with the same
/// spawned tile; several undos and redos in a row step back and forth through
/// the same moves. A new swipe after an undo draws a new random tile and
/// forgets the undone moves, so they can't be redone. The limit counts moves
/// on either side of the current state: after five moves the last three can
/// be undone, and after undoing two of them and swiping again, the remaining
/// one and the new swipe can.
///
/// ## Winning
///
/// The first time the board has a tile of at least the rules' winning value,
/// ``hasWon`` and ``shouldPresentWin`` turn `true`. ``shouldPresentWin``
/// stays `true`, whatever else happens, until the UI has congratulated the
/// player and calls ``acknowledgeWin()`` (the player chose to keep playing),
/// so a quick swipe can't skip the win. It happens once per game: undoing the
/// winning move doesn't take the win back, and reaching the tile again, by a
/// new move or by redo, doesn't present it again. Only ``restart()`` starts
/// over. Play goes on after a win until no move is possible
/// (``isGameOver``); a move can win and end the game at once.
///
/// ## High score
///
/// ``highScore`` is the best score reached in the session's variant, including
/// earlier games. The session raises it whenever the score beats it; nothing
/// lowers it, and ``restart()`` keeps it, so code that shows the session never
/// updates the high score itself. Get the sessions the player sees from
/// ``GameStore/loadSession(for:newGameSeed:)``, which starts from the stored
/// high score, and start new games with ``restart()``.
///
/// ## Saving
///
/// A session is `Codable` and decodes to an equal session that continues
/// exactly as the original would have, including undo, redo and the tiles
/// still to be drawn. Save it with ``GameStore``, whose format is versioned,
/// rather than encoding it directly.
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

    /// The most recent moves that can be undone, oldest first.
    private var undoHistory: [HistoryEntry] = []
    /// The moves that can be redone, in the order they would be replayed.
    private var redoMoves: [MoveRecord] = []
    /// Whether the game has been won and whether that still needs presenting.
    private var win: WinState

    /// Draws the starting tiles and the tile each move spawns.
    private var generator: SplitMix64

    /// Starts a new game: the board gets the rules' starting tiles, drawn from
    /// a generator seeded with `seed`.
    ///
    /// For the game the player sees, use
    /// ``GameStore/loadSession(for:newGameSeed:)`` instead, so the high score
    /// isn't lost.
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
        self.win = WinState(rules: rules, board: board)
    }

    /// Starts a game on a given board, for example to set up a test or a
    /// preview close to a win or to game over.
    ///
    /// If `board` already has a winning tile, the game counts as just won:
    /// ``shouldPresentWin`` is `true` until ``acknowledgeWin()``.
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
        self.win = WinState(rules: rules, board: board)
    }

    /// The number of moves the session remembers for undo.
    public static let undoLimit = 3

    /// Whether ``undo()`` can take back a move.
    public var canUndo: Bool {
        !undoHistory.isEmpty
    }

    /// Whether ``redo()`` can play an undone move again.
    public var canRedo: Bool {
        !redoMoves.isEmpty
    }

    /// The number of moves that ``undo()`` can take back in a row, at most
    /// ``undoLimit``.
    public var undoCount: Int {
        undoHistory.count
    }

    /// The number of undone moves that ``redo()`` can play again in a row.
    public var redoCount: Int {
        redoMoves.count
    }

    /// Whether a tile of at least the rules' winning value has been reached in
    /// this game. Undo doesn't reset it; ``restart()`` does.
    public var hasWon: Bool {
        win != .notWon
    }

    /// Whether the UI should tell the player they won and offer to keep
    /// playing: the game was won and ``acknowledgeWin()`` hasn't been called
    /// since. Moves, undo and redo don't change it.
    public var shouldPresentWin: Bool {
        win == .pending
    }

    /// Records that the player has seen the win and keeps playing, so
    /// ``shouldPresentWin`` turns `false`. Does nothing otherwise.
    public mutating func acknowledgeWin() {
        if win == .pending {
            win = .acknowledged
        }
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
    ///   a swipe is ignored: the session is left exactly as it was, and the
    ///   moves that can be redone are kept.
    @discardableResult
    public mutating func move(_ direction: Direction) -> Move? {
        guard let move = rules.move(direction, on: board, using: &generator) else { return nil }
        redoMoves.removeAll()
        apply(move)
        return move
    }

    /// Takes back the most recent move, restoring the board and score from
    /// before it. The move can then be redone.
    ///
    /// - Returns: Whether a move was undone: `false` if there was nothing to
    ///   undo.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let entry = undoHistory.popLast() else { return false }
        redoMoves.insert(entry.move, at: 0)
        board = entry.before.board
        score = entry.before.score
        return true
    }

    /// Plays the most recently undone move again, with the same spawned tile.
    ///
    /// - Returns: The move, for animating it like ``move(_:)``'s result, or
    ///   `nil` if there is nothing to redo.
    @discardableResult
    public mutating func redo() -> Move? {
        guard !redoMoves.isEmpty else { return nil }
        let record = redoMoves.removeFirst()
        guard let move = record.replayed(on: board) else {
            preconditionFailure("An undone move doesn't replay on the board it was undone to")
        }
        apply(move)
        return move
    }

    /// Starts a new game in the same variant with new starting tiles and a
    /// score of 0. Moves of the previous game can't be undone or redone, and
    /// the new game can be won again. The high score is kept.
    public mutating func restart() {
        board = rules.startingBoard(using: &generator)
        score = 0
        win = WinState(rules: rules, board: board)
        undoHistory.removeAll()
        redoMoves.removeAll()
    }

    /// Raises the high score to `score` if that is higher, for example to a
    /// stored high score newer than the session's.
    mutating func raiseHighScore(to score: Int) {
        highScore = max(highScore, score)
    }

    /// Makes `move`, which was played on the current board, the current state
    /// and remembers it for undo, forgetting the oldest move beyond the limit.
    private mutating func apply(_ move: Move) {
        let before = Snapshot(board: board, score: score)
        if undoHistory.count == Self.undoLimit {
            undoHistory.removeFirst()
        }
        undoHistory.append(HistoryEntry(before: before, move: MoveRecord(direction: move.direction, spawn: move.spawn)))
        let after = before.advanced(by: move)
        board = after.board
        score = after.score
        raiseHighScore(to: score)
        if win == .notWon, rules.isWinning(board) {
            win = .pending
        }
    }
}

/// A board and score at some point of a game.
struct Snapshot: Hashable, Sendable {
    var board: Board
    var score: Int
}

/// What it takes to replay a move exactly on the board it was played on.
struct MoveRecord: Hashable, Sendable {
    var direction: Direction
    var spawn: Spawn

    /// The move, replayed on `board`, or `nil` if it doesn't fit `board`.
    func replayed(on board: Board) -> Move? {
        Move(direction: direction, spawn: spawn, on: board)
    }
}

/// A move that can be undone: the state before it and how to replay it.
struct HistoryEntry: Hashable, Sendable {
    var before: Snapshot
    var move: MoveRecord
}

/// Where a game stands with respect to winning.
enum WinState: String, Hashable, Sendable {
    /// No winning tile has been reached in this game.
    case notWon
    /// A winning tile was reached and the win hasn't been acknowledged yet.
    case pending
    /// The game was won and the player keeps playing.
    case acknowledged

    /// The state of a game that starts on `board`: a starting board can win
    /// in variants with a small winning value.
    init(rules: GameRules, board: Board) {
        self = rules.isWinning(board) ? .pending : .notWon
    }
}

extension GameSession: Codable {
    /// The keys of the encoded session. The encoding is part of the saved
    /// game format (see ``GameStore``), so existing keys and their meaning
    /// must not change.
    private enum CodingKeys: String, CodingKey {
        case rules, board, score, highScore, win, undo, redo, generator
    }

    /// Decodes a session, rejecting data that isn't a consistent game: the
    /// boards must fit the rules, and every recorded move must replay on the
    /// board it was played on and lead to the next state, so undo and redo
    /// can't fail later.
    ///
    /// This encoding, including that of the rules, boards and other values it
    /// contains, is version 1 of the saved game format (see ``GameStore``).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rules = try container.decode(GameRules.self, forKey: .rules)
        board = try container.decode(Board.self, forKey: .board)
        score = try container.decode(Int.self, forKey: .score)
        highScore = try container.decode(Int.self, forKey: .highScore)
        win = try container.decode(WinState.self, forKey: .win)
        undoHistory = try container.decode([HistoryEntry].self, forKey: .undo)
        redoMoves = try container.decode([MoveRecord].self, forKey: .redo)
        generator = try container.decode(SplitMix64.self, forKey: .generator)
        if let problem {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: problem))
        }
    }

    /// Encodes the session. `undo` lists the moves that can be undone, oldest
    /// first, each as the board and score `before` it and the `move` itself
    /// (its direction and spawn); `redo` lists the moves that can be redone
    /// in the order they would be replayed.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rules, forKey: .rules)
        try container.encode(board, forKey: .board)
        try container.encode(score, forKey: .score)
        try container.encode(highScore, forKey: .highScore)
        try container.encode(win, forKey: .win)
        try container.encode(undoHistory, forKey: .undo)
        try container.encode(redoMoves, forKey: .redo)
        try container.encode(generator, forKey: .generator)
    }

    /// Why the session isn't a consistent game, or `nil` if it is.
    private var problem: String? {
        let current = Snapshot(board: board, score: score)
        guard current.fits(rules) else { return "The board or score doesn't fit the rules" }
        guard board.tileCount > 0 else { return "The board is empty" }
        guard undoHistory.count + redoMoves.count <= Self.undoLimit else { return "The history is too long" }
        if win == .notWon && rules.isWinning(board) {
            return "The board has a winning tile but the game isn't won"
        }
        var next: Snapshot?
        for entry in undoHistory {
            guard entry.before.fits(rules), next == nil || next == entry.before,
                let after = entry.before.replaying(entry.move)
            else { return "The undo history isn't a line of play leading to the board" }
            next = after
        }
        guard next == nil || next == current else { return "The undo history doesn't lead to the board" }
        var state = current
        for record in redoMoves {
            guard let after = state.replaying(record) else { return "A move to redo doesn't fit its board" }
            state = after
        }
        guard highScore >= state.score else { return "The high score is below a score that was reached" }
        return nil
    }
}

extension Snapshot {
    /// Whether the board fits `rules` and the score isn't negative.
    func fits(_ rules: GameRules) -> Bool {
        rules.accepts(board) && score >= 0
    }

    /// The state after replaying `record` on this one, or `nil` if it doesn't
    /// fit the board.
    func replaying(_ record: MoveRecord) -> Snapshot? {
        record.replayed(on: board).map(advanced(by:))
    }

    /// The state after `move`, which was played on this state's board. The
    /// score stops at `Int.max` rather than trapping, so a tampered saved
    /// score can't crash the game.
    func advanced(by move: Move) -> Snapshot {
        let (sum, overflow) = score.addingReportingOverflow(move.scoreDelta)
        return Snapshot(board: move.board, score: overflow ? .max : sum)
    }
}

extension Snapshot: Codable {}
extension MoveRecord: Codable {}
extension WinState: Codable {}

extension HistoryEntry: Codable {}
