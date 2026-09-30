import GameCore
import Observation
import os

/// The game on screen: a `GameSession` that is saved after every change, and
/// the tiles that show its board.
///
/// Every change to the session goes through one place, ``update(_:_:)``,
/// which also brings ``layout`` to the session's board, records the change
/// (``lastChange``) and saves the session, so the tiles, the session and the
/// saved game never disagree. Views read the state below and call the
/// actions; they don't touch the session.
@MainActor
@Observable
final class GameModel {
    /// A message shown over the board.
    enum Overlay: Hashable {
        /// The winning tile was reached; the player can keep playing or start
        /// a new game. Moves, undo and redo wait until they choose.
        case win
        /// No move is possible. Undo still works.
        case gameOver
    }

    /// Why games aren't being saved.
    enum StorageProblem: Equatable {
        /// The saved game couldn't be read, so this launch plays without
        /// saving rather than replacing it.
        case couldNotLoad
        /// The last save failed; the next change tries again.
        case couldNotSave
    }

    /// A change the player made, for the score's "+N" animation and for
    /// VoiceOver announcements. Each change has its own id, so equal changes
    /// in a row are each noticed.
    struct Change: Equatable {
        enum Kind: Equatable {
            case move, redo, undo, newGame, keepPlaying
        }

        let id: Int
        let kind: Kind
        /// How the tiles moved, for a move or redo.
        let transition: TileTransition?
        /// The points the change scored: positive only for a move or redo
        /// that merged tiles.
        let points: Int
    }

    /// The game being played.
    private(set) var session: GameSession
    /// The board's tiles with identities, and how the last move changed them
    /// (`lastTransition`), which the board view animates. Moves and redo
    /// animate; undo and a new game replace the tiles.
    private(set) var layout: TileLayout
    /// The last change, or `nil` if there was none since launch.
    private(set) var lastChange: Change?
    /// Why games aren't being saved, or `nil` while saving works.
    private(set) var storageProblem: StorageProblem?
    /// Whether the player is being asked to confirm a new game, which can't
    /// be undone.
    var isConfirmingNewGame = false

    private let store: GameStore
    /// Whether the session changed since it was last saved.
    @ObservationIgnored private var needsSave = false
    @ObservationIgnored private var changeCount = 0
    /// How the game was started, to try loading again (see
    /// ``retryLoadingIfNeeded()``).
    private let configuration: LaunchConfiguration
    private let randomSeed: UInt64

    private static let logger = Logger(subsystem: "com.crypticswarm.game4096", category: "GameModel")

    /// Starts the game `configuration` describes (see
    /// `LaunchConfiguration.startingSession(from:randomSeed:)`), saving it in
    /// `storage`.
    ///
    /// If the saved game can't be read, a new game starts (with the stored
    /// high score, if that can be read) and isn't saved, so the saved game
    /// survives; see ``retryLoadingIfNeeded()``.
    ///
    /// The app gets `storage` from `configuration.storage`; tests pass their
    /// own.
    init(
        configuration: LaunchConfiguration, storage: any GameStorage,
        randomSeed: UInt64 = .random(in: .min ... .max)
    ) {
        let store = GameStore(storage: storage)
        let session: GameSession
        do {
            session = try configuration.startingSession(from: store, randomSeed: randomSeed)
            storageProblem = nil
        } catch {
            Self.logger.error(
                "Couldn't load the saved game, so it won't be saved over: \(String(describing: error), privacy: .public)"
            )
            let highScore = (try? store.highScore(for: configuration.rules)) ?? 0
            session = configuration.newSession(highScore: highScore, randomSeed: randomSeed)
            storageProblem = .couldNotLoad
        }
        self.store = store
        self.configuration = configuration
        self.randomSeed = randomSeed
        self.session = session
        layout = TileLayout(board: session.board)
    }

    var score: Int { session.score }
    var highScore: Int { session.highScore }
    /// The tile that wins the game.
    var winningValue: Int { session.rules.winningValue }

    /// The message to show over the board, if any. A move can win and end
    /// the game at once; the win comes first.
    var overlay: Overlay? {
        if session.shouldPresentWin {
            .win
        } else if session.isGameOver {
            .gameOver
        } else {
            nil
        }
    }

    /// Whether ``undo()`` can take back a move now.
    var canUndo: Bool {
        overlay != .win && session.canUndo
    }

    /// Whether ``redo()`` can play an undone move again now.
    var canRedo: Bool {
        overlay != .win && session.canRedo
    }

    /// Slides the tiles in `direction` and spawns a tile, unless the slide
    /// changes nothing or the win is being presented.
    ///
    /// - Returns: Whether the tiles moved.
    @discardableResult
    func perform(_ direction: Direction) -> Bool {
        guard overlay != .win else { return false }
        return update(.move) { $0.move(direction) }
    }

    /// Takes back the last move, if ``canUndo``.
    func undo() {
        guard canUndo else { return }
        update(.undo) { session in
            session.undo()
            return nil
        }
    }

    /// Plays the last undone move again, with the same new tile, if
    /// ``canRedo``.
    func redo() {
        guard canRedo else { return }
        update(.redo) { $0.redo() }
    }

    /// Dismisses the win and goes on playing.
    func keepPlaying() {
        update(.keepPlaying) { session in
            session.acknowledgeWin()
            return nil
        }
    }

    /// Asks the player to confirm a new game (see ``isConfirmingNewGame``).
    func requestNewGame() {
        isConfirmingNewGame = true
    }

    /// Starts a new game after the player confirmed it. The high score is
    /// kept; the previous game's moves can't be undone.
    func confirmNewGame() {
        isConfirmingNewGame = false
        update(.newGame) { session in
            session.restart()
            return nil
        }
    }

    /// Saves the game if a change hasn't been saved yet, which happens only
    /// after a failed save: every change saves the game. The app calls it
    /// when it moves to the background.
    func saveIfNeeded() {
        if needsSave {
            save()
        }
    }

    /// Loads the saved game again if it couldn't be read at launch and the
    /// player hasn't played since, for example because the app was launched
    /// in the background before the device was first unlocked. The app calls
    /// it when it becomes active. Not while a new game is being confirmed,
    /// which would then replace the loaded game.
    func retryLoadingIfNeeded() {
        guard storageProblem == .couldNotLoad, lastChange == nil, !isConfirmingNewGame,
            let session = try? configuration.startingSession(from: store, randomSeed: randomSeed)
        else { return }
        self.session = session
        layout.reset(to: session.board)
        storageProblem = nil
    }

    private func save() {
        // Never save over a game that couldn't be read.
        guard storageProblem != .couldNotLoad else { return }
        do {
            try store.save(session)
            needsSave = false
            if storageProblem == .couldNotSave {
                storageProblem = nil
            }
        } catch {
            Self.logger.error("Couldn't save the game: \(String(describing: error), privacy: .public)")
            storageProblem = .couldNotSave
        }
    }

    /// The one place the session changes: applies `change` to the session,
    /// then brings the tiles to its board (animating the move `change`
    /// returns, or replacing the tiles if the board changed otherwise),
    /// records the change as `kind` and saves.
    ///
    /// - Returns: Whether the session changed.
    @discardableResult
    private func update(_ kind: Change.Kind, _ change: (inout GameSession) -> Move?) -> Bool {
        // Changes a copy, so that an action that changes nothing doesn't
        // notify observers.
        var next = session
        let move = change(&next)
        guard next != session else { return false }
        session = next
        var transition: TileTransition?
        if let move {
            transition = layout.apply(move)
        } else if layout.board != session.board {
            layout.reset(to: session.board)
        }
        changeCount += 1
        lastChange = Change(id: changeCount, kind: kind, transition: transition, points: move?.scoreDelta ?? 0)
        needsSave = true
        save()
        return true
    }
}

/// The words of each message, shown over the board and announced to
/// VoiceOver.
extension GameModel.Overlay {
    /// The message's title, such as "You win!".
    var title: String {
        switch self {
        case .win: "You win!"
        case .gameOver: "Game over!"
        }
    }

    /// The line under the title.
    func detail(winningValue: Int, canUndo: Bool) -> String {
        switch self {
        case .win: "You made \(winningValue). Keep going for a bigger tile?"
        case .gameOver: canUndo ? "No moves left. You can still undo." : "No moves left."
        }
    }
}
