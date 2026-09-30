/// Options the app reads from its launch arguments, so UI tests and
/// development builds can start a reproducible game and keep it apart from
/// the player's saved game.
///
/// | Argument | Effect |
/// | --- | --- |
/// | `-seed <UInt64>` | Seeds the random number generator of a new game (not of a saved game, which keeps its own), so it is reproducible. |
/// | `-board <notation>` | Starts from this board instead of the saved game, for example `-board "2,2,0,0;0,0,0,0;0,0,0,0;0,0,0,4"` (see ``Board/init(notation:)``). Its size picks the board size. |
/// | `-score <Int>` | The score of the `-board` game (0 by default). Needs `-board`. |
/// | `-highScore <Int>` | Raises the high score to at least this. |
/// | `-storage <memory or folder>` | Where games and high scores are saved (see ``Storage``). |
///
/// README.md ("Launch arguments") describes how the app uses them. Other
/// arguments are ignored, since the system and XCTest pass their own.
public struct LaunchConfiguration: Hashable, Sendable {
    /// Where the app saves games and high scores.
    public enum Storage: Hashable, Sendable {
        /// In a folder with this name in the app's Application Support
        /// directory.
        case folder(String)
        /// In memory only: nothing is read at launch or kept after the app
        /// quits.
        case memory

        /// Where the player's games are saved.
        public static let standard = Storage.folder("Saves")

        /// The value of `-storage` that selects ``memory``.
        static let memoryArgument = "memory"

        /// Whether `name` can be a folder: not empty, not `.` or `..`, not
        /// ``memoryArgument`` and without `/`, so it names a single folder
        /// inside Application Support.
        static func isValidFolderName(_ name: String) -> Bool {
            !["", ".", "..", memoryArgument].contains(name) && !name.contains("/")
        }
    }

    /// The argument that sets ``seed``.
    public static let seedArgument = "-seed"
    /// The argument that sets ``board``.
    public static let boardArgument = "-board"
    /// The argument that sets ``score``.
    public static let scoreArgument = "-score"
    /// The argument that sets ``highScore``.
    public static let highScoreArgument = "-highScore"
    /// The argument that sets ``storage``.
    public static let storageArgument = "-storage"

    /// The seed for a new game's random number generator, or `nil` for a
    /// random seed.
    public var seed: UInt64?
    /// The board to start from, or `nil` to continue the saved game.
    public var board: Board?
    /// The score of the ``board`` game.
    public var score: Int
    /// A high score to start from if the stored one is lower.
    public var highScore: Int
    /// Where games and high scores are saved.
    public var storage: Storage

    /// Creates a configuration, for example for a UI test to launch the app
    /// with its ``arguments``.
    ///
    /// - Precondition: `board`, if any, has a size in
    ///   ``GameRules/supportedBoardSizes`` and a tile; a nonzero `score`
    ///   comes with a board; scores aren't negative; a `storage` folder is a
    ///   single folder name other than `memory`.
    public init(
        seed: UInt64? = nil, board: Board? = nil, score: Int = 0, highScore: Int = 0, storage: Storage = .standard
    ) {
        if let board {
            precondition(
                GameRules.supportedBoardSizes.contains(board.size), "Board size \(board.size) isn't supported")
            precondition(board.tileCount > 0, "A game needs a tile on the board")
        }
        precondition(score == 0 || board != nil, "A score needs a board")
        precondition(score >= 0 && highScore >= 0, "Scores can't be negative")
        if case .folder(let name) = storage {
            precondition(Storage.isValidFolderName(name), "Invalid storage folder \"\(name)\"")
        }
        self.seed = seed
        self.board = board
        self.score = score
        self.highScore = highScore
        self.storage = storage
    }

    /// Parses launch arguments such as `CommandLine.arguments`. Each option's
    /// value is the argument after it; when an option repeats, the last wins.
    ///
    /// - Throws: ``LaunchConfigurationError`` if an option lacks a value, its
    ///   value is invalid, or `-score` is given without `-board`.
    public init(arguments: [String]) throws(LaunchConfigurationError) {
        self.init()
        var remaining = arguments[...]
        var hasScore = false
        while let argument = remaining.popFirst() {
            func value() throws(LaunchConfigurationError) -> String {
                guard let text = remaining.popFirst() else { throw .missingValue(argument) }
                return text
            }
            switch argument {
            case Self.seedArgument:
                let text = try value()
                guard let seed = UInt64(text) else { throw .invalidSeed(text) }
                self.seed = seed
            case Self.boardArgument:
                board = try Self.parseBoard(value())
            case Self.scoreArgument:
                score = try Self.parseScore(value())
                hasScore = true
            case Self.highScoreArgument:
                highScore = try Self.parseScore(value())
            case Self.storageArgument:
                storage = try Self.parseStorage(value())
            default:
                continue
            }
        }
        if hasScore && board == nil {
            throw .scoreWithoutBoard
        }
    }

    private static func parseBoard(_ text: String) throws(LaunchConfigurationError) -> Board {
        let board: Board
        do {
            board = try Board(notation: text)
        } catch {
            throw .invalidBoard(text, error)
        }
        guard GameRules.supportedBoardSizes.contains(board.size) else {
            throw .invalidBoard(text, .unsupportedSize(board.size))
        }
        guard board.tileCount > 0 else { throw .emptyBoard(text) }
        return board
    }

    private static func parseScore(_ text: String) throws(LaunchConfigurationError) -> Int {
        guard let score = Int(text), score >= 0 else { throw .invalidScore(text) }
        return score
    }

    private static func parseStorage(_ text: String) throws(LaunchConfigurationError) -> Storage {
        if text == Storage.memoryArgument {
            return .memory
        }
        guard Storage.isValidFolderName(text) else { throw .invalidStorage(text) }
        return .folder(text)
    }

    /// Launch arguments that parse back to this configuration.
    public var arguments: [String] {
        var arguments: [String] = []
        if let seed {
            arguments += [Self.seedArgument, String(seed)]
        }
        if let board {
            arguments += [Self.boardArgument, board.notation]
        }
        if score != 0 {
            arguments += [Self.scoreArgument, String(score)]
        }
        if highScore != 0 {
            arguments += [Self.highScoreArgument, String(highScore)]
        }
        switch storage {
        case .standard: break
        case .memory: arguments += [Self.storageArgument, Storage.memoryArgument]
        case .folder(let name): arguments += [Self.storageArgument, name]
        }
        return arguments
    }

    /// The rules to play: ``GameRules/classic``, or for a ``board`` of
    /// another size, the classic rules on that size (see
    /// ``GameRules/classic(boardSize:)``).
    public var rules: GameRules {
        board.map { GameRules.classic(boardSize: $0.size) } ?? .classic
    }

    /// The game to start with: a game on ``board`` with ``score``, if there is
    /// a board, otherwise the game saved in `store` (or a new one, see
    /// ``GameStore/loadSession(for:newGameSeed:)``). Its high score is at
    /// least the stored one and ``highScore``.
    ///
    /// - Parameter randomSeed: The seed to use if ``seed`` is `nil`.
    /// - Throws: If `store` fails to read (see
    ///   ``GameStore/loadSession(for:newGameSeed:)``).
    public func startingSession(from store: GameStore, randomSeed: UInt64) throws -> GameSession {
        if board != nil {
            return newSession(highScore: try store.highScore(for: rules), randomSeed: randomSeed)
        }
        var session = try store.loadSession(for: rules, newGameSeed: seed ?? randomSeed)
        session.raiseHighScore(to: highScore)
        return session
    }

    /// The game to start with when there is no saved game to continue, such
    /// as when it couldn't be read: a game on ``board`` with ``score``, or a
    /// new game. Its high score is at least `highScore` and ``highScore``.
    ///
    /// - Parameter randomSeed: The seed to use if ``seed`` is `nil`.
    public func newSession(highScore: Int = 0, randomSeed: UInt64) -> GameSession {
        let seed = seed ?? randomSeed
        let highScore = max(highScore, self.highScore)
        guard let board else { return GameSession(rules: rules, seed: seed, highScore: highScore) }
        return GameSession(rules: rules, board: board, score: score, seed: seed, highScore: highScore)
    }
}

/// Why ``LaunchConfiguration/init(arguments:)`` rejected the arguments.
public enum LaunchConfigurationError: Error, Hashable, Sendable {
    /// An option is the last argument, with no value after it.
    case missingValue(String)
    /// The value of `-seed` isn't a `UInt64`.
    case invalidSeed(String)
    /// The value of `-board` isn't a valid board of a supported size.
    case invalidBoard(String, BoardError)
    /// The value of `-board` has no tile.
    case emptyBoard(String)
    /// The value of `-score` or `-highScore` isn't a non-negative `Int`.
    case invalidScore(String)
    /// The value of `-storage` is neither `memory` nor a valid folder name.
    case invalidStorage(String)
    /// `-score` was given without `-board`.
    case scoreWithoutBoard
}
