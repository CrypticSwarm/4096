import Foundation
import GameCore
import Testing

@testable import Game4096

@MainActor
struct GameModelTests {
    /// Every direction but up changes this board (see BoardUITests).
    nonisolated static let fixture = try! Board(notation: "2,2,4,8;4,8,2,0;0,0,0,0;0,0,0,0")

    static func model(
        board: Board? = fixture, seed: UInt64 = 42, storage: any GameStorage = InMemoryGameStorage()
    ) -> GameModel {
        GameModel(configuration: LaunchConfiguration(seed: seed, board: board), storage: storage, randomSeed: 7)
    }

    /// The session saved in `storage`.
    static func saved(in storage: any GameStorage, rules: GameRules = .classic) throws -> GameSession {
        try GameStore(storage: storage).loadSession(for: rules, newGameSeed: 0)
    }

    /// Checks that the tiles show the session's board and that the session
    /// is saved.
    static func expectInSync(
        _ model: GameModel, storage: any GameStorage, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        #expect(model.layout.board == model.session.board, sourceLocation: sourceLocation)
        #expect(try saved(in: storage) == model.session, sourceLocation: sourceLocation)
    }

    @Test func startsFromTheConfiguredBoard() {
        let model = Self.model()
        #expect(model.session.board == Self.fixture)
        #expect(model.layout.board == Self.fixture)
        #expect(model.layout.lastTransition == nil)
        #expect(model.score == 0)
        #expect(model.overlay == nil)
        #expect(!model.canUndo && !model.canRedo)
        #expect(model.storageProblem == nil)
    }

    @Test func continuesTheSavedGameWithItsHistory() throws {
        let storage = InMemoryGameStorage()
        var session = GameSession(rules: .classic, board: Self.fixture, seed: 3, highScore: 50)
        session.move(.left)
        session.move(.down)
        session.undo()
        try GameStore(storage: storage).save(session)

        let model = GameModel(configuration: LaunchConfiguration(), storage: storage, randomSeed: 1)

        #expect(model.session == session)
        #expect(model.layout.board == session.board)
        #expect(model.layout.lastTransition == nil)
        #expect(model.canUndo && model.canRedo)
        #expect(model.highScore == 50)
    }

    @Test func performPlaysTheSessionsMoveAndSaves() throws {
        let storage = InMemoryGameStorage()
        let model = Self.model(storage: storage)

        #expect(model.perform(.left))

        var expected = GameSession(rules: .classic, board: Self.fixture, seed: 42)
        let played = expected.move(.left)
        let move = try #require(played)
        #expect(model.session == expected)
        #expect(model.layout.lastTransition?.direction == .left)
        #expect(model.layout.lastTransition?.spawned.position == move.spawn.position)
        #expect(model.score == 4)
        #expect(model.highScore == model.score)
        try Self.expectInSync(model, storage: storage)
    }

    @Test func swipeThatChangesNothingIsIgnoredAndNotSaved() {
        let storage = TestStorage()
        let model = Self.model(storage: storage)
        let before = model.layout

        #expect(!model.perform(.up))

        #expect(model.layout == before)
        #expect(model.lastChange == nil)
        #expect(storage.writeCount == 0)
    }

    @Test func undoReplacesTheTilesAndRedoAnimatesTheSameMove() throws {
        let storage = InMemoryGameStorage()
        let model = Self.model(storage: storage)
        model.perform(.left)
        let afterMove = model.session

        model.undo()

        #expect(model.session.board == Self.fixture)
        #expect(model.score == 0)
        #expect(model.highScore == afterMove.score)
        #expect(model.layout.lastTransition == nil)
        #expect(!model.canUndo && model.canRedo)
        try Self.expectInSync(model, storage: storage)

        model.redo()

        #expect(model.session.board == afterMove.board)
        #expect(model.score == afterMove.score)
        #expect(model.layout.lastTransition?.direction == .left)
        #expect(model.canUndo && !model.canRedo)
        try Self.expectInSync(model, storage: storage)
    }

    @Test func undoAndRedoFollowTheSessionsLimit() {
        let model = Self.model()
        for direction in [Direction.left, .down, .right, .up] {
            #expect(model.perform(direction))
        }
        for _ in 0..<GameSession.undoLimit {
            #expect(model.canUndo)
            model.undo()
        }
        #expect(!model.canUndo)
        #expect(model.canRedo)
        let beforeExtraUndo = model.session
        model.undo()
        #expect(model.session == beforeExtraUndo)

        model.redo()
        #expect(model.perform(.left) || model.perform(.right) || model.perform(.up) || model.perform(.down))
        #expect(!model.canRedo)
        model.redo()
        #expect(!model.canRedo)
    }

    /// Whatever the player does, the tiles show the session's board and the
    /// saved game is the session.
    @Test func tilesAndSavedGameFollowTheSession() throws {
        let storage = InMemoryGameStorage()
        let model = Self.model(board: nil, seed: 11, storage: storage)
        var generator = SplitMix64(seed: 2026)
        for _ in 0..<300 {
            switch Int.random(in: 0..<10, using: &generator) {
            case 0..<5: model.perform(Direction.allCases.randomElement(using: &generator)!)
            case 5..<7: model.undo()
            case 7..<9: model.redo()
            default:
                model.requestNewGame()
                model.confirmNewGame()
            }
            if model.overlay == .win {
                model.keepPlaying()
            }
            #expect(model.layout.tiles.count == model.session.board.tileCount)
            // Nothing is saved before the first change.
            if model.lastChange != nil {
                try Self.expectInSync(model, storage: storage)
            }
        }
        #expect(model.lastChange != nil)
    }

    @Test func newGameWaitsForConfirmationAndCantBeUndone() throws {
        let storage = InMemoryGameStorage()
        let model = Self.model(storage: storage)
        model.perform(.left)
        model.perform(.down)
        model.undo()
        let before = model.session

        model.requestNewGame()

        #expect(model.isConfirmingNewGame)
        #expect(model.session == before)

        model.confirmNewGame()

        var expected = before
        expected.restart()
        #expect(!model.isConfirmingNewGame)
        #expect(model.session == expected)
        #expect(model.score == 0)
        #expect(model.highScore == before.highScore)
        #expect(!model.canUndo && !model.canRedo)
        #expect(model.layout.lastTransition == nil)
        #expect(model.lastChange?.kind == .newGame)
        try Self.expectInSync(model, storage: storage)
    }

    @Test func winIsPresentedOnceAndHoldsMovesUntilDismissed() throws {
        let storage = InMemoryGameStorage()
        let model = Self.model(board: try Board(notation: "2048,2048,0,0;0,0,0,0;0,0,0,0;0,0,0,2"), storage: storage)

        model.perform(.left)

        #expect(model.overlay == .win)
        #expect(model.session.board[Position(row: 0, column: 0)] == 4096)
        #expect(!model.canUndo)
        let won = model.session
        #expect(!model.perform(.down))
        model.undo()
        #expect(model.session == won)

        model.keepPlaying()

        #expect(model.overlay == nil)
        #expect(model.canUndo)
        try Self.expectInSync(model, storage: storage)

        // Reaching the tile again, by redo or by a new move, doesn't show it
        // again.
        model.undo()
        model.redo()
        #expect(model.session.board[Position(row: 0, column: 0)] == 4096)
        #expect(model.overlay == nil)
        model.undo()
        #expect(model.perform(.left))
        #expect(model.session.board[Position(row: 0, column: 0)] == 4096)
        #expect(model.overlay == nil)
    }

    /// A move can win and end the game at once: the win shows first, and
    /// after Keep playing the game over message, with Undo.
    @Test func winComesBeforeGameOver() throws {
        // Swiping left makes 4096 and leaves no move, whatever spawns.
        let model = Self.model(board: try Board(notation: "2048,2048,4,8;8,2,32,16;2,8,2,8;8,2,8,2"))

        model.perform(.left)

        #expect(model.session.isGameOver)
        #expect(model.overlay == .win)
        #expect(!model.canUndo)

        model.keepPlaying()

        #expect(model.overlay == .gameOver)
        #expect(model.canUndo)
        #expect(model.lastChange?.kind == .keepPlaying)
    }

    /// A win the player hadn't dismissed when the app quit is shown again.
    @Test func pendingWinIsShownAfterRelaunch() throws {
        let storage = InMemoryGameStorage()
        let model = Self.model(board: try Board(notation: "2048,2048,0,0;0,0,0,0;0,0,0,0;0,0,0,2"), storage: storage)
        model.perform(.left)
        #expect(model.overlay == .win)

        let relaunched = GameModel(configuration: LaunchConfiguration(), storage: storage, randomSeed: 1)

        #expect(relaunched.session == model.session)
        #expect(relaunched.overlay == .win)
    }

    @Test func gameOverLetsThePlayerUndo() throws {
        // Swiping left leaves the board full with no merges, whichever tile
        // spawns in the only free cell.
        let board = try Board(notation: "2,4,2,4;4,2,4,2;2,4,2,8;4,2,8,8")
        let model = Self.model(board: board)

        model.perform(.left)

        #expect(model.overlay == .gameOver)
        #expect(model.canUndo)

        model.undo()

        #expect(model.overlay == nil)
        #expect(model.session.board == board)
    }

    @Test func changesAreRecordedWithTheirPoints() throws {
        let model = Self.model()
        #expect(model.lastChange == nil)

        model.perform(.left)
        let move = try #require(model.lastChange)
        #expect(move.kind == .move)
        #expect(move.points == 4)
        #expect(move.transition == model.layout.lastTransition)

        model.undo()
        let undo = try #require(model.lastChange)
        #expect(undo.kind == .undo)
        #expect(undo.points == 0)
        #expect(undo.transition == nil)

        model.redo()
        let redo = try #require(model.lastChange)
        #expect(redo.kind == .redo)
        #expect(redo.points == 4)
        #expect(redo.transition?.direction == .left)
        #expect(Set([move.id, undo.id, redo.id]).count == 3)
    }

    @Test func unreadableSaveIsNeitherLoadedNorOverwritten() throws {
        let storage = TestStorage()
        var saved = GameSession(rules: .classic, seed: 1, highScore: 300)
        playUntilScored(&saved)
        try GameStore(storage: storage).save(saved)
        storage.failingKeys = ["game-classic"]

        let model = GameModel(configuration: LaunchConfiguration(seed: 5), storage: storage, randomSeed: 1)

        #expect(model.storageProblem == .couldNotLoad)
        // A new game, keeping the high score, which could still be read.
        #expect(model.session == GameSession(rules: .classic, seed: 5, highScore: 300))
        storage.failingKeys = []
        let writes = storage.writeCount
        playUntilScored(model)
        model.saveIfNeeded()
        #expect(storage.writeCount == writes)
        #expect(try Self.saved(in: storage) == saved)
        #expect(model.storageProblem == .couldNotLoad)

        // Once played, the game isn't replaced by the saved one.
        model.retryLoadingIfNeeded()
        #expect(model.storageProblem == .couldNotLoad)
        #expect(model.session.score > 0)
    }

    /// A saved game that couldn't be read at launch is loaded when the app
    /// becomes active, if the player hasn't played yet.
    @Test func unreadableSaveIsLoadedLater() throws {
        let storage = TestStorage()
        var saved = GameSession(rules: .classic, seed: 1)
        playUntilScored(&saved)
        try GameStore(storage: storage).save(saved)
        storage.failingKeys = nil

        let model = GameModel(configuration: LaunchConfiguration(seed: 5), storage: storage, randomSeed: 1)
        #expect(model.storageProblem == .couldNotLoad)
        #expect(model.highScore == 0)

        model.retryLoadingIfNeeded()
        #expect(model.storageProblem == .couldNotLoad)

        storage.failingKeys = []
        // Not behind the alert confirming a new game.
        model.requestNewGame()
        model.retryLoadingIfNeeded()
        #expect(model.storageProblem == .couldNotLoad)
        model.isConfirmingNewGame = false
        model.retryLoadingIfNeeded()

        #expect(model.storageProblem == nil)
        #expect(model.session == saved)
        #expect(model.layout.board == saved.board)
        #expect(model.lastChange == nil)
        model.perform(.left)
        try Self.expectInSync(model, storage: storage)
    }

    @Test func failedSaveIsReportedAndRetried() throws {
        let storage = TestStorage()
        let model = Self.model(storage: storage)
        storage.failingKeys = nil

        model.perform(.left)

        #expect(model.storageProblem == .couldNotSave)
        #expect(model.session.score == 4)

        storage.failingKeys = []
        model.perform(.down)

        #expect(model.storageProblem == nil)
        try Self.expectInSync(model, storage: storage)
    }

    /// Moving to the background saves only a change that wasn't saved, so
    /// launching with a fixture and leaving doesn't replace the saved game.
    @Test func backgroundSavesOnlyUnsavedChanges() throws {
        let storage = TestStorage()
        let model = Self.model(storage: storage)

        model.saveIfNeeded()
        #expect(storage.writeCount == 0)

        storage.failingKeys = nil
        model.perform(.left)
        storage.failingKeys = []
        model.saveIfNeeded()

        #expect(model.storageProblem == nil)
        try Self.expectInSync(model, storage: storage)
        let writes = storage.writeCount
        model.saveIfNeeded()
        #expect(storage.writeCount == writes)
    }

    @Test func fixtureOfAnotherSizeIsPlayed() throws {
        let board = try Board(notation: "2,2,0,0,0;0,0,0,0,0;0,0,0,0,0;0,0,0,0,0;0,0,0,0,0")
        let storage = InMemoryGameStorage()
        let model = Self.model(board: board, storage: storage)
        model.perform(.right)
        #expect(model.layout.board.size == 5)
        #expect(model.layout.board[Position(row: 0, column: 4)] == 4)
        #expect(try Self.saved(in: storage, rules: model.session.rules) == model.session)
    }
}

/// Plays swipes in turn until the score is positive.
@MainActor
private func playUntilScored(_ model: GameModel) {
    var index = 0
    while model.score == 0 {
        model.perform(Direction.allCases[index % 4])
        index += 1
    }
}

/// Swipes in turn until the score is positive.
private func playUntilScored(_ session: inout GameSession) {
    var index = 0
    while session.score == 0 {
        session.move(Direction.allCases[index % 4])
        index += 1
    }
}

/// Storage in memory whose reads and writes can be made to fail, and that
/// counts writes.
private final class TestStorage: GameStorage, @unchecked Sendable {
    struct Failure: Error {}

    // @unchecked: every access to the variables holds `lock`.
    private let lock = NSLock()
    private let contents = InMemoryGameStorage()
    private var _failingKeys: Set<String>? = []
    private var _writeCount = 0

    /// The keys whose reads and writes fail, or `nil` for all keys.
    var failingKeys: Set<String>? {
        get { lock.withLock { _failingKeys } }
        set { lock.withLock { _failingKeys = newValue } }
    }

    var writeCount: Int {
        lock.withLock { _writeCount }
    }

    func data(forKey key: String) throws -> Data? {
        try check(key)
        return contents.data(forKey: key)
    }

    func setData(_ data: Data, forKey key: String) throws {
        try check(key)
        lock.withLock { _writeCount += 1 }
        contents.setData(data, forKey: key)
    }

    private func check(_ key: String) throws {
        if failingKeys?.contains(key) ?? true {
            throw Failure()
        }
    }
}
