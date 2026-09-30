import GameCore
import Observation

/// The state of the game on screen, played with the engine directly.
///
/// This is a stand-in until the game session (undo, scores, persistence)
/// exists; swapping it in should only change this class's internals. Views
/// depend on nothing but ``layout``, ``perform(_:)`` and ``newGame()``.
@MainActor
@Observable
final class GameModel {
    /// The board's tiles with identities, and how the last move changed them
    /// (`lastTransition`), which the board view animates.
    private(set) var layout: TileLayout

    private let rules: GameRules
    @ObservationIgnored private var generator: SplitMix64

    /// Starts the game `configuration` describes: its board, or a new game
    /// drawn from its seed (or a random seed).
    init(configuration: LaunchConfiguration) {
        rules = configuration.rules
        var generator = SplitMix64(seed: configuration.seed ?? UInt64.random(in: .min ... .max))
        layout = TileLayout(board: configuration.board ?? rules.startingBoard(using: &generator))
        self.generator = generator
    }

    /// Slides the tiles in `direction` and spawns a tile, unless the slide
    /// changes nothing.
    ///
    /// - Returns: Whether the tiles moved.
    @discardableResult
    func perform(_ direction: Direction) -> Bool {
        guard let move = rules.move(direction, on: layout.board, using: &generator) else { return false }
        layout.apply(move)
        return true
    }

    /// Replaces the board with a new game's.
    func newGame() {
        layout.reset(to: rules.startingBoard(using: &generator))
    }
}
