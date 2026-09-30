/// The parameters of a game variant, such as the classic 4×4 game.
///
/// Sliding and merging work the same in every variant; the rules choose the
/// board size, the tile that wins, how many tiles a game starts with and how
/// new tiles are drawn. Play is endless: winning doesn't end the game, which
/// ends only when no move is possible (see ``Board/hasAvailableMoves``).
public struct GameRules: Identifiable, Hashable, Codable, Sendable {
    /// A stable identifier for the variant, such as `"classic"`, for keying
    /// data like high scores. Keep it unchanged for as long as the variant's
    /// parameters stay the same, and don't reuse it for other parameters.
    public let id: String
    /// The number of rows and of columns.
    public let boardSize: Int
    /// A game is won once a tile of at least this value exists.
    public let winningValue: Int
    /// The number of tiles spawned on the empty board to start a game.
    public let startingTileCount: Int
    /// How the value of each new tile is drawn.
    public let spawnDistribution: SpawnDistribution

    /// The board sizes rules may use.
    public static let supportedBoardSizes = 2...Board.maxSize

    /// The classic game: a 4×4 board, two starting tiles and the classic spawn
    /// distribution, played to a 4096 tile.
    public static let classic = GameRules(id: "classic")

    /// The classic game on a board of another size: ``classic`` for 4×4, and
    /// otherwise the classic parameters with the id `"classic-<size>x<size>"`,
    /// such as `"classic-5x5"`. Use it wherever such a variant is created, so
    /// its saved game and high score are always found under the same id.
    ///
    /// - Precondition: `boardSize` is in ``supportedBoardSizes``.
    public static func classic(boardSize: Int) -> GameRules {
        boardSize == classic.boardSize
            ? classic : GameRules(id: "classic-\(boardSize)x\(boardSize)", boardSize: boardSize)
    }

    /// Creates rules for a variant; parameters default to the classic game's.
    ///
    /// - Precondition: `id` isn't empty, `boardSize` is in
    ///   ``supportedBoardSizes``, `winningValue` is a valid tile value (a power
    ///   of two from 2 through ``Board/maxTileValue``) and `startingTileCount`
    ///   is between 1 and the number of cells.
    public init(
        id: String,
        boardSize: Int = 4,
        winningValue: Int = 4096,
        startingTileCount: Int = 2,
        spawnDistribution: SpawnDistribution = .classic
    ) {
        self.id = id
        self.boardSize = boardSize
        self.winningValue = winningValue
        self.startingTileCount = startingTileCount
        self.spawnDistribution = spawnDistribution
        if let problem {
            preconditionFailure(problem)
        }
    }

    /// Decodes rules, rejecting parameters that
    /// ``init(id:boardSize:winningValue:startingTileCount:spawnDistribution:)``
    /// would.
    ///
    /// Every key is required. A parameter added later must be decoded with
    /// `decodeIfPresent` and default to its classic value, so that saved rules
    /// from earlier versions still load.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        boardSize = try container.decode(Int.self, forKey: .boardSize)
        winningValue = try container.decode(Int.self, forKey: .winningValue)
        startingTileCount = try container.decode(Int.self, forKey: .startingTileCount)
        spawnDistribution = try container.decode(SpawnDistribution.self, forKey: .spawnDistribution)
        if let problem {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: problem))
        }
    }

    /// Whether `board` can be played under these rules: its size is
    /// ``boardSize``. Use it to validate a board restored from storage or
    /// built for a test before playing on it.
    public func accepts(_ board: Board) -> Bool {
        board.size == boardSize
    }

    /// Returns the board a new game starts with: ``startingTileCount`` tiles
    /// spawned one after another on an empty board.
    public func startingBoard(using generator: inout some RandomNumberGenerator) -> Board {
        var board = Board(size: boardSize)
        for _ in 0..<startingTileCount {
            // Validation guarantees startingTileCount fits the board.
            board = board.placing(spawnDistribution.randomSpawn(on: board, using: &generator)!)
        }
        return board
    }

    /// Whether `board` is winning under these rules: it has a tile of at
    /// least ``winningValue``.
    public func isWinning(_ board: Board) -> Bool {
        (board.highestTileValue ?? 0) >= winningValue
    }

    /// Plays a move: slides `board` in `direction`, then spawns a tile drawn
    /// from ``spawnDistribution`` in a random empty cell.
    ///
    /// - Returns: The move, or `nil` if sliding doesn't change the board. Such
    ///   a swipe isn't a move: nothing spawns and `generator` isn't used.
    /// - Precondition: ``accepts(_:)`` is `true` for `board`.
    public func move(
        _ direction: Direction, on board: Board, using generator: inout some RandomNumberGenerator
    ) -> Move? {
        precondition(accepts(board), "A \(board.size)×\(board.size) board doesn't fit rules \"\(id)\"")
        let slide = board.sliding(direction)
        guard !slide.isNoOp else { return nil }
        // A slide that changes the board always leaves a cell free: a merge
        // removes a tile, and without merges tiles can only have moved if a
        // cell was empty, and the number of tiles stays the same.
        let spawn = spawnDistribution.randomSpawn(on: slide.board, using: &generator)!
        return Move(direction: direction, slide: slide, spawn: spawn)
    }

    /// Why these parameters are invalid, or `nil` if they are valid.
    private var problem: String? {
        if id.isEmpty {
            return "Rules need a non-empty id"
        }
        if !Self.supportedBoardSizes.contains(boardSize) {
            return "Board size \(boardSize) is outside \(Self.supportedBoardSizes)"
        }
        if Board.exponent(ofTileValue: winningValue) == nil {
            return "Winning value \(winningValue) is not a valid tile value"
        }
        if !(1...boardSize * boardSize).contains(startingTileCount) {
            return "Starting tile count \(startingTileCount) doesn't fit a \(boardSize)×\(boardSize) board"
        }
        return nil
    }
}
