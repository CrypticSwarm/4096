/// The parameters of a game variant, such as the classic 4×4 game.
///
/// Sliding and merging work the same in every variant; the rules choose the
/// board size, the tile that wins, how many tiles a game starts with and how
/// new tiles are drawn. Play is endless: winning doesn't end the game, which
/// ends only when no move is possible (see ``Board/hasAvailableMoves``).
public struct GameRules: Identifiable, Hashable, Codable, Sendable {
    /// A stable identifier for the variant, such as `"classic"`, for keying
    /// data like high scores. Keep it unchanged for as long as the variant's
    /// parameters stay the same.
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
    public static let supportedBoardSizes = 2...16

    /// The classic game: a 4×4 board, two starting tiles and the classic spawn
    /// distribution, played to a 4096 tile.
    public static let classic = GameRules(id: "classic")

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
        if let problem = Self.problem(
            id: id, boardSize: boardSize, winningValue: winningValue, startingTileCount: startingTileCount)
        {
            preconditionFailure(problem)
        }
        self.id = id
        self.boardSize = boardSize
        self.winningValue = winningValue
        self.startingTileCount = startingTileCount
        self.spawnDistribution = spawnDistribution
    }

    /// Decodes rules, rejecting parameters that ``init(id:boardSize:winningValue:startingTileCount:spawnDistribution:)``
    /// would.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        boardSize = try container.decode(Int.self, forKey: .boardSize)
        winningValue = try container.decode(Int.self, forKey: .winningValue)
        startingTileCount = try container.decode(Int.self, forKey: .startingTileCount)
        spawnDistribution = try container.decode(SpawnDistribution.self, forKey: .spawnDistribution)
        if let problem = Self.problem(
            id: id, boardSize: boardSize, winningValue: winningValue, startingTileCount: startingTileCount)
        {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: problem))
        }
    }

    /// Returns the board a new game starts with: ``startingTileCount`` tiles
    /// spawned one after another on an empty board.
    public func startingBoard(using generator: inout some RandomNumberGenerator) -> Board {
        var board = Board(size: boardSize)
        for _ in 0..<startingTileCount {
            if let spawn = spawnDistribution.randomSpawn(on: board, using: &generator) {
                board = board.placing(spawn)
            }
        }
        return board
    }

    /// Whether `board` has a tile of at least ``winningValue``.
    public func isWon(_ board: Board) -> Bool {
        (board.highestTileValue ?? 0) >= winningValue
    }

    /// Plays a move: slides `board` in `direction`, then spawns a tile drawn
    /// from ``spawnDistribution`` in a random empty cell.
    ///
    /// - Returns: The move, or `nil` if sliding doesn't change the board. Such
    ///   a swipe isn't a move: nothing spawns and `generator` isn't used.
    public func move(
        _ direction: Direction, on board: Board, using generator: inout some RandomNumberGenerator
    ) -> Move? {
        let slide = board.sliding(direction)
        guard !slide.isNoOp,
            let spawn = spawnDistribution.randomSpawn(on: slide.board, using: &generator)
        else { return nil }
        return Move(direction: direction, slide: slide, spawn: spawn)
    }

    private static func problem(id: String, boardSize: Int, winningValue: Int, startingTileCount: Int) -> String? {
        if id.isEmpty {
            return "Rules need a non-empty id"
        }
        if !supportedBoardSizes.contains(boardSize) {
            return "Board size \(boardSize) is outside \(supportedBoardSizes)"
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
