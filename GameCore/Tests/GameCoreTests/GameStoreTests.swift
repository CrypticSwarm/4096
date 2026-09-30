import Foundation
import GameCore
import Testing

struct GameStoreTests {
    static let threeByThree = GameRules(id: "3x3", boardSize: 3, winningValue: 64)
    static let fiveByFive = GameRules(id: "5x5", boardSize: 5, startingTileCount: 3)

    /// The session ``fixture`` holds: three moves, the last one undone, with
    /// a generator state above `Int64.max`.
    static func fixtureSession() -> GameSession {
        var session = GameSession(rules: threeByThree, seed: 1 << 63, highScore: 30)
        for direction in [Direction.left, .up, .right] {
            session.move(direction)
        }
        session.undo()
        return session
    }

    /// A saved game in format version 1. It must keep loading in every later
    /// version of the app.
    static let fixture = """
        {"session":{"board":[[4,2,0],[0,0,2],[0,0,0]],"generator":{"state":12550055787829450962},"highScore":30,\
        "redo":[{"direction":"right","spawn":{"position":{"column":1,"row":2},"value":2}}],\
        "rules":{"boardSize":3,"id":"3x3","spawnDistribution":{"outcomes":[{"value":2,"weight":9},\
        {"value":4,"weight":1}]},"startingTileCount":2,"winningValue":64},"score":4,\
        "undo":[{"before":{"board":[[0,0,2],[0,2,0],[0,0,0]],"score":0},"move":{"direction":"left",\
        "spawn":{"position":{"column":1,"row":0},"value":2}}},{"before":{"board":[[2,2,0],[2,0,0],[0,0,0]],\
        "score":0},"move":{"direction":"up","spawn":{"position":{"column":2,"row":1},"value":2}}}],\
        "win":"notWon"},"version":1}
        """

    static func storage(game: String? = nil, highScores: String? = nil) -> InMemoryGameStorage {
        var contents: [String: Data] = [:]
        contents["game-3x3"] = game.map { Data($0.utf8) }
        contents["high-scores"] = highScores.map { Data($0.utf8) }
        return InMemoryGameStorage(contents)
    }

    static func text(_ data: Data?) -> String? {
        data.map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func savesInThePinnedFormat() throws {
        let storage = InMemoryGameStorage()

        try GameStore(storage: storage).save(Self.fixtureSession())

        #expect(Self.text(storage.data(forKey: "game-3x3")) == Self.fixture)
        #expect(Self.text(storage.data(forKey: "high-scores")) == #"{"scores":{"3x3":30},"version":1}"#)
    }

    @Test func loadsThePinnedFormat() throws {
        let store = GameStore(storage: Self.storage(game: Self.fixture))

        var session = store.loadSession(for: Self.threeByThree, newGameSeed: 0)

        #expect(session == Self.fixtureSession())
        #expect(session.score == 4 && session.highScore == 30)
        #expect(session.undoCount == 2 && session.redoCount == 1)
        #expect(session.redo()?.spawn == Spawn(position: at(2, 1), value: 2))
    }

    @Test func restoresAGameExactly() throws {
        let store = GameStore(storage: InMemoryGameStorage())
        var original = GameSessionCodingTests.midGame()

        try store.save(original)
        var restored = store.loadSession(for: .classic, newGameSeed: 1)

        #expect(restored == original)
        #expect(restored.redo() == original.redo())
        for index in 0..<100 {
            let direction = Direction.allCases[index % 4]
            #expect(restored.move(direction) == original.move(direction))
        }
        #expect(restored == original)
    }

    @Test func restoresAPendingWin() throws {
        let store = GameStore(storage: InMemoryGameStorage())
        var session = try WinTests.session(WinTests.oneMergeFromEight)
        session.move(.left)

        try store.save(session)

        #expect(store.loadSession(for: WinTests.toEight, newGameSeed: 1).shouldPresentWin)
    }

    @Test func startsANewGameWhenNothingIsSaved() {
        let store = GameStore(storage: InMemoryGameStorage())
        #expect(store.loadSession(for: .classic, newGameSeed: 42) == GameSession(rules: .classic, seed: 42))
        #expect(store.highScore(for: .classic) == 0)
    }

    /// Saved games that must not be restored, each with the stored high score
    /// of 70.
    static let unusableGames: [(String, String)] = [
        ("empty", ""),
        ("not JSON", "garbage"),
        ("truncated", String(fixture.prefix(fixture.count / 2))),
        ("empty object", "{}"),
        ("no session", #"{"version":1}"#),
        ("later version", fixture.replacingOccurrences(of: #""version":1}"#, with: #""version":2}"#)),
        ("version as text", fixture.replacingOccurrences(of: #""version":1}"#, with: #""version":"1"}"#)),
        ("board of another size", fixture.replacingOccurrences(of: #""boardSize":3"#, with: #""boardSize":4"#)),
        ("other rules", fixture.replacingOccurrences(of: #""winningValue":64"#, with: #""winningValue":128"#)),
        ("inconsistent history", fixture.replacingOccurrences(of: #""score":4"#, with: #""score":8"#)),
    ]

    @Test(arguments: unusableGames)
    func unusableSavedGameStartsANewGameAndKeepsTheHighScore(problem: String, game: String) {
        let store = GameStore(storage: Self.storage(game: game, highScores: #"{"scores":{"3x3":70},"version":1}"#))

        let session = store.loadSession(for: Self.threeByThree, newGameSeed: 5)

        #expect(session == GameSession(rules: Self.threeByThree, seed: 5, highScore: 70), "\(problem)")
    }

    @Test func savingOverAnUnusableGameReplacesIt() throws {
        let storage = Self.storage(game: "garbage")
        let store = GameStore(storage: storage)
        var session = store.loadSession(for: Self.threeByThree, newGameSeed: 5)
        session.move(.left)

        try store.save(session)

        #expect(store.loadSession(for: Self.threeByThree, newGameSeed: 6) == session)
    }

    @Test func savingRaisesTheStoredHighScore() throws {
        let store = GameStore(storage: InMemoryGameStorage())
        var session = UndoRedoTests.play(30)[30]
        try store.save(session)
        #expect(store.highScore(for: .classic) == session.highScore)

        // Undoing doesn't lower it, nor does saving a session with a lower one.
        session.undo()
        try store.save(session)
        #expect(store.highScore(for: .classic) == session.highScore)
        try store.save(GameSession(rules: .classic, seed: 1))
        #expect(store.highScore(for: .classic) == session.highScore)
    }

    @Test func restartKeepsTheHighScore() throws {
        let store = GameStore(storage: InMemoryGameStorage())
        var session = UndoRedoTests.play(30)[30]
        let highScore = session.highScore
        try store.save(session)

        session.restart()
        try store.save(session)
        let restored = store.loadSession(for: .classic, newGameSeed: 1)

        #expect(restored.score == 0)
        #expect(restored.highScore == highScore)
        #expect(store.highScore(for: .classic) == highScore)
    }

    @Test func loadedGameGetsAHigherStoredHighScore() throws {
        let store = GameStore(
            storage: Self.storage(game: Self.fixture, highScores: #"{"scores":{"3x3":500},"version":1}"#))
        #expect(store.loadSession(for: Self.threeByThree, newGameSeed: 0).highScore == 500)
    }

    @Test(arguments: [
        "", "garbage", #"{"scores":{"3x3":"many"},"version":1}"#, #"{"scores":{"3x3":900},"version":2}"#,
    ])
    func unreadableHighScoresFallBackToTheSavedGames(highScores: String) throws {
        let store = GameStore(storage: Self.storage(game: Self.fixture, highScores: highScores))

        #expect(store.highScore(for: Self.threeByThree) == 0)
        let session = store.loadSession(for: Self.threeByThree, newGameSeed: 0)
        #expect(session == Self.fixtureSession())
        #expect(session.highScore == 30)

        try store.save(session)
        #expect(store.highScore(for: Self.threeByThree) == 30)
    }

    @Test func negativeStoredHighScoreCountsAsNone() {
        let store = GameStore(storage: Self.storage(highScores: #"{"scores":{"3x3":-5},"version":1}"#))
        #expect(store.highScore(for: Self.threeByThree) == 0)
        #expect(store.loadSession(for: Self.threeByThree, newGameSeed: 1).highScore == 0)
    }

    @Test func variantsKeepSeparateGamesAndHighScores() throws {
        let storage = InMemoryGameStorage()
        let store = GameStore(storage: storage)
        var classic = UndoRedoTests.play(30)[30]
        var fiveByFive = GameSession(rules: Self.fiveByFive, seed: 3)
        playUntilScored(&fiveByFive)
        #expect(classic.highScore != fiveByFive.highScore)

        try store.save(classic)
        try store.save(fiveByFive)

        #expect(store.loadSession(for: .classic, newGameSeed: 0) == classic)
        #expect(store.loadSession(for: Self.fiveByFive, newGameSeed: 0) == fiveByFive)
        #expect(store.highScore(for: .classic) == classic.highScore)
        #expect(store.highScore(for: Self.fiveByFive) == fiveByFive.highScore)
        #expect(storage.data(forKey: "game-classic") != nil)
        #expect(storage.data(forKey: "game-5x5") != nil)

        // Restarting one variant leaves the other alone.
        classic.restart()
        try store.save(classic)
        #expect(store.loadSession(for: Self.fiveByFive, newGameSeed: 0) == fiveByFive)
    }

    @Test func storageErrorsOnLoadStartANewGame() throws {
        let store = GameStore(storage: FailingStorage())
        #expect(store.loadSession(for: .classic, newGameSeed: 3) == GameSession(rules: .classic, seed: 3))
        #expect(store.highScore(for: .classic) == 0)
    }

    @Test func storageErrorsOnSaveAreThrown() {
        let store = GameStore(storage: FailingStorage())
        #expect(throws: FailingStorage.Failure.self) {
            try store.save(GameSession(rules: .classic, seed: 3))
        }
    }
}

/// Storage whose every read and write fails.
struct FailingStorage: GameStorage {
    struct Failure: Error {}

    func data(forKey key: String) throws -> Data? {
        throw Failure()
    }

    func setData(_ data: Data, forKey key: String) throws {
        throw Failure()
    }
}
