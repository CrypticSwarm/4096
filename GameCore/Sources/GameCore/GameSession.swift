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
/// ``shouldPresentWin`` turns `true` so the UI can congratulate the player,
/// until ``acknowledgeWin()`` (the player chose to keep playing) or the next
/// move, undo or redo. That happens once per game: ``hasWon`` stays `true`
/// even if the winning move is undone, so reaching the tile again doesn't
/// present the win again. Only ``restart()`` starts over. Play goes on after
/// a win until no move is possible (``isGameOver``); a move can win and end
/// the game at once.
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

    /// The most recent moves that can be undone, oldest first.
    private var undoHistory: [HistoryEntry] = []
    /// The moves that can be redone, the next one last.
    private var redoMoves: [MoveRecord] = []
    /// Whether the game has been won and whether that still needs presenting.
    private var win: WinState

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
        self.win = WinState(rules: rules, board: board)
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
    /// this game. Undo doesn't reset it.
    public var hasWon: Bool {
        win != .notWon
    }

    /// Whether the UI should now tell the player they won and offer to keep
    /// playing: the game was just won and the player hasn't moved on yet.
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
        if undoHistory.count == Self.undoLimit {
            undoHistory.removeFirst()
        }
        apply(move)
        return move
    }

    /// Takes back the most recent move, restoring the board and score from
    /// before it. The move can then be redone.
    ///
    /// - Returns: The move that was taken back, for animating it in reverse,
    ///   or `nil` if there is nothing to undo.
    @discardableResult
    public mutating func undo() -> Move? {
        guard let entry = undoHistory.popLast() else { return nil }
        guard let move = entry.move.replayed(on: entry.before.board) else {
            preconditionFailure("A recorded move doesn't replay on the board it was played on")
        }
        redoMoves.append(entry.move)
        board = entry.before.board
        score = entry.before.score
        acknowledgeWin()
        return move
    }

    /// Plays the most recently undone move again, with the same spawned tile.
    ///
    /// - Returns: The move, for animating it like ``move(_:)``'s result, or
    ///   `nil` if there is nothing to redo.
    @discardableResult
    public mutating func redo() -> Move? {
        guard let record = redoMoves.popLast() else { return nil }
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

    /// Makes `move`, which was played on the current board, the current state
    /// and remembers it for undo.
    ///
    /// The caller makes room in the history: at most ``undoLimit`` moves can
    /// be undone or redone in total, so redoing always fits.
    private mutating func apply(_ move: Move) {
        undoHistory.append(HistoryEntry(before: Snapshot(board: board, score: score), move: MoveRecord(move)))
        board = move.board
        score = Self.adding(move.scoreDelta, to: score)
        highScore = max(highScore, score)
        acknowledgeWin()
        if win == .notWon, rules.isWinning(board) {
            win = .pending
        }
    }

    /// Adds points to a score, stopping at `Int.max` rather than trapping, so
    /// a tampered saved score can't crash the game.
    static func adding(_ points: Int, to score: Int) -> Int {
        let (sum, overflow) = score.addingReportingOverflow(points)
        return overflow ? .max : sum
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

    init(direction: Direction, spawn: Spawn) {
        self.direction = direction
        self.spawn = spawn
    }

    init(_ move: Move) {
        self.init(direction: move.direction, spawn: move.spawn)
    }

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
    /// A winning tile was just reached and the win hasn't been presented yet.
    case pending
    /// The game was won and the player keeps playing.
    case acknowledged

    /// The state of a game that starts on `board`: a starting board can win
    /// in variants with a small winning value.
    init(rules: GameRules, board: Board) {
        self = rules.isWinning(board) ? .pending : .notWon
    }
}
