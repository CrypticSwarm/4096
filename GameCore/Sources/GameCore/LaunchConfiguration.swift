/// Options the app reads from its launch arguments, so UI tests and
/// development builds can start a reproducible game.
///
/// | Argument | Effect |
/// | --- | --- |
/// | `-seed <UInt64>` | Seeds the random number generator, so spawns (and the starting board, without `-board`) are reproducible. |
/// | `-board <notation>` | Starts from this board instead of a new game, for example `-board "2,2,0,0;0,0,0,0;0,0,0,0;0,0,0,4"` (see ``Board/init(notation:)``). Its size picks the board size. |
///
/// Other arguments are ignored, since the system and XCTest pass their own.
public struct LaunchConfiguration: Hashable, Sendable {
    /// The argument that sets ``seed``.
    public static let seedArgument = "-seed"
    /// The argument that sets ``board``.
    public static let boardArgument = "-board"

    /// The seed for the game's random number generator, or `nil` for a random seed.
    public var seed: UInt64?
    /// The board to start from, or `nil` for a new game.
    public var board: Board?

    /// Creates a configuration, for example for a UI test to launch the app
    /// with its ``arguments``.
    ///
    /// - Precondition: `board`, if any, has a size in ``GameRules/supportedBoardSizes``.
    public init(seed: UInt64? = nil, board: Board? = nil) {
        if let board {
            precondition(
                GameRules.supportedBoardSizes.contains(board.size), "Board size \(board.size) isn't supported")
        }
        self.seed = seed
        self.board = board
    }

    /// Parses launch arguments such as `CommandLine.arguments`. Each option's
    /// value is the argument after it; when an option repeats, the last wins.
    ///
    /// - Throws: ``LaunchConfigurationError`` if an option lacks a value or its
    ///   value is invalid.
    public init(arguments: [String]) throws(LaunchConfigurationError) {
        self.init()
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            switch argument {
            case Self.seedArgument:
                guard let text = remaining.popFirst() else { throw .missingValue(argument) }
                guard let seed = UInt64(text) else { throw .invalidSeed(text) }
                self.seed = seed
            case Self.boardArgument:
                guard let text = remaining.popFirst() else { throw .missingValue(argument) }
                let board: Board
                do {
                    board = try Board(notation: text)
                } catch {
                    throw .invalidBoard(text, error)
                }
                guard GameRules.supportedBoardSizes.contains(board.size) else {
                    throw .invalidBoard(text, .unsupportedSize(board.size))
                }
                self.board = board
            default:
                continue
            }
        }
    }

    /// Launch arguments that parse back to this configuration.
    public var arguments: [String] {
        (seed.map { [Self.seedArgument, String($0)] } ?? [])
            + (board.map { [Self.boardArgument, $0.notation] } ?? [])
    }

    /// The rules to play: ``GameRules/classic``, or for a ``board`` of
    /// another size, the classic rules on that size with the id
    /// `"classic-<size>x<size>"`.
    public var rules: GameRules {
        guard let board, board.size != GameRules.classic.boardSize else { return .classic }
        return GameRules(id: "classic-\(board.size)x\(board.size)", boardSize: board.size)
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
}
