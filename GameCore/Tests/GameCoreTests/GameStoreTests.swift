import Foundation
import GameCore
import Testing

struct GameStoreTests {
    static let threeByThree = GameRules(id: "3x3-to64", boardSize: 3, winningValue: 64)
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
        "rules":{"boardSize":3,"id":"3x3-to64","spawnDistribution":{"outcomes":[{"value":2,"weight":9},\
        {"value":4,"weight":1}]},"startingTileCount":2,"winningValue":64},"score":4,\
        "undo":[{"before":{"board":[[0,0,2],[0,2,0],[0,0,0]],"score":0},"move":{"direction":"left",\
        "spawn":{"position":{"column":1,"row":0},"value":2}}},{"before":{"board":[[2,2,0],[2,0,0],[0,0,0]],\
        "score":0},"move":{"direction":"up","spawn":{"position":{"column":2,"row":1},"value":2}}}],\
        "win":"notWon"},"version":1}
        """

    /// The session ``wonFixture`` holds: a pending win, one move to undo and
    /// two to redo.
    static func wonFixtureSession() throws -> GameSession {
        var session = try WinTests.session(WinTests.oneMergeFromEight, seed: 3)
        for direction in [Direction.left, .right, .down] {
            session.move(direction)
        }
        session.undo()
        session.undo()
        return session
    }

    /// Another saved game in format version 1, which must keep loading.
    static let wonFixture = """
        {"session":{"board":[[8,2,0],[0,0,0],[0,0,0]],"generator":{"state":13064056694810536065},"highScore":8,\
        "redo":[{"direction":"right","spawn":{"position":{"column":0,"row":2},"value":2}},\
        {"direction":"down","spawn":{"position":{"column":1,"row":0},"value":2}}],\
        "rules":{"boardSize":3,"id":"to8","spawnDistribution":{"outcomes":[{"value":2,"weight":9},\
        {"value":4,"weight":1}]},"startingTileCount":2,"winningValue":8},"score":8,\
        "undo":[{"before":{"board":[[4,4,0],[0,0,0],[0,0,0]],"score":0},"move":{"direction":"left",\
        "spawn":{"position":{"column":1,"row":0},"value":2}}}],"win":"pending"},"version":1}
        """

    static func storage(game: String? = nil, highScores: String? = nil) -> InMemoryGameStorage {
        var contents: [String: Data] = [:]
        contents["game-3x3-to64"] = game.map { Data($0.utf8) }
        contents["high-scores"] = highScores.map { Data($0.utf8) }
        return InMemoryGameStorage(contents)
    }

    static func text(_ data: Data?) -> String? {
        data.map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func savesInThePinnedFormat() throws {
        let storage = InMemoryGameStorage()
        let store = GameStore(storage: storage)

        try store.save(Self.fixtureSession())
        try store.save(Self.wonFixtureSession())

        #expect(Self.text(storage.data(forKey: "game-3x3-to64")) == Self.fixture)
        #expect(Self.text(storage.data(forKey: "game-to8")) == Self.wonFixture)
        #expect(Self.text(storage.data(forKey: "high-scores")) == #"{"scores":{"3x3-to64":30,"to8":8},"version":1}"#)
    }

    /// Checks what the fixture holds value by value, so the test doesn't
    /// depend on the generator reproducing the game.
    @Test func loadsThePinnedFormat() throws {
        let store = GameStore(storage: Self.storage(game: Self.fixture))

        var session = try store.loadSession(for: Self.threeByThree, newGameSeed: 0)

        #expect(session.board.rows == [[4, 2, 0], [0, 0, 2], [0, 0, 0]])
        #expect(session.score == 4 && session.highScore == 30)
        #expect(!session.hasWon)
        #expect(session.undoCount == 2 && session.redoCount == 1)
        var undone = session
        undone.undo()
        undone.undo()
        #expect(undone.board.rows == [[0, 0, 2], [0, 2, 0], [0, 0, 0]])
        #expect(undone.score == 0)
        let redone = session.redo()
        #expect(redone?.direction == .right)
        #expect(redone?.spawn == Spawn(position: at(2, 1), value: 2))
    }

    @Test func loadsThePinnedFormatOfAWonGame() throws {
        let storage = InMemoryGameStorage(["game-to8": Data(Self.wonFixture.utf8)])

        var session = try GameStore(storage: storage).loadSession(for: WinTests.toEight, newGameSeed: 0)

        #expect(session.board.rows == [[8, 2, 0], [0, 0, 0], [0, 0, 0]])
        #expect(session.score == 8 && session.highScore == 8)
        #expect(session.hasWon && session.shouldPresentWin)
        #expect(session.undoCount == 1 && session.redoCount == 2)
        let first = session.redo()
        let second = session.redo()
        #expect(first?.direction == .right && first?.spawn == Spawn(position: at(2, 0), value: 2))
        #expect(second?.direction == .down && second?.spawn == Spawn(position: at(0, 1), value: 2))
        #expect(session.board.rows == [[0, 2, 0], [0, 0, 0], [2, 8, 2]])

        let acknowledged = Self.wonFixture.replacingOccurrences(of: #""win":"pending""#, with: #""win":"acknowledged""#)
        storage.setData(Data(acknowledged.utf8), forKey: "game-to8")
        session = try GameStore(storage: storage).loadSession(for: WinTests.toEight, newGameSeed: 0)
        #expect(session.hasWon && !session.shouldPresentWin)
    }

    @Test func restoresAGameExactly() throws {
        let store = GameStore(storage: InMemoryGameStorage())
        var original = midGame()

        try store.save(original)
        var restored = try store.loadSession(for: .classic, newGameSeed: 1)

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

        #expect(try store.loadSession(for: WinTests.toEight, newGameSeed: 1).shouldPresentWin)
    }

    @Test func startsANewGameWhenNothingIsSaved() throws {
        let store = GameStore(storage: InMemoryGameStorage())
        #expect(try store.loadSession(for: .classic, newGameSeed: 42) == GameSession(rules: .classic, seed: 42))
        #expect(try store.highScore(for: .classic) == 0)
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
        ("earlier version", fixture.replacingOccurrences(of: #""version":1}"#, with: #""version":0}"#)),
        ("negative version", fixture.replacingOccurrences(of: #""version":1}"#, with: #""version":-1}"#)),
        ("version as text", fixture.replacingOccurrences(of: #""version":1}"#, with: #""version":"1"}"#)),
        ("board of another size", fixture.replacingOccurrences(of: #""boardSize":3"#, with: #""boardSize":4"#)),
        ("other rules", fixture.replacingOccurrences(of: #""winningValue":64"#, with: #""winningValue":128"#)),
        ("inconsistent history", fixture.replacingOccurrences(of: #""score":4"#, with: #""score":8"#)),
        (
            "too large",
            fixture.replacingOccurrences(
                of: "{", with: "{" + String(repeating: " ", count: 1 << 20), options: [],
                range: fixture.startIndex..<fixture.index(after: fixture.startIndex))
        ),
    ]

    @Test(arguments: unusableGames)
    func unusableSavedGameStartsANewGameAndKeepsTheHighScore(problem: String, game: String) throws {
        let store = GameStore(storage: Self.storage(game: game, highScores: #"{"scores":{"3x3-to64":70},"version":1}"#))

        let session = try store.loadSession(for: Self.threeByThree, newGameSeed: 5)

        #expect(session == GameSession(rules: Self.threeByThree, seed: 5, highScore: 70), "\(problem)")
    }

    @Test func savingOverAnUnusableGameReplacesIt() throws {
        let storage = Self.storage(game: "garbage")
        let store = GameStore(storage: storage)
        var session = try store.loadSession(for: Self.threeByThree, newGameSeed: 5)
        session.move(.left)

        try store.save(session)

        #expect(try store.loadSession(for: Self.threeByThree, newGameSeed: 6) == session)
    }

    @Test func savingRaisesTheStoredHighScore() throws {
        let store = GameStore(storage: InMemoryGameStorage())
        var session = playedGame(moves: 30).states[30]
        try store.save(session)
        #expect(try store.highScore(for: .classic) == session.highScore)

        // Undoing doesn't lower it, nor does saving a session with a lower one.
        session.undo()
        try store.save(session)
        #expect(try store.highScore(for: .classic) == session.highScore)
        try store.save(GameSession(rules: .classic, seed: 1))
        #expect(try store.highScore(for: .classic) == session.highScore)
    }

    @Test func restartKeepsTheHighScore() throws {
        let store = GameStore(storage: InMemoryGameStorage())
        var session = playedGame(moves: 30).states[30]
        let highScore = session.highScore
        try store.save(session)

        session.restart()
        try store.save(session)
        let restored = try store.loadSession(for: .classic, newGameSeed: 1)

        #expect(restored.score == 0)
        #expect(restored.highScore == highScore)
        #expect(try store.highScore(for: .classic) == highScore)
    }

    @Test func loadedGameGetsAHigherStoredHighScore() throws {
        let store = GameStore(
            storage: Self.storage(game: Self.fixture, highScores: #"{"scores":{"3x3-to64":500},"version":1}"#))
        #expect(try store.loadSession(for: Self.threeByThree, newGameSeed: 0).highScore == 500)
    }

    @Test(arguments: [
        "", "garbage", #"{"scores":{"3x3-to64":"many"},"version":1}"#, #"{"version":1}"#,
        #"{"scores":{"3x3-to64":900},"version":0}"#,
    ])
    func unreadableHighScoresFallBackToTheSavedGames(highScores: String) throws {
        let store = GameStore(storage: Self.storage(game: Self.fixture, highScores: highScores))

        #expect(try store.highScore(for: Self.threeByThree) == 0)
        let session = try store.loadSession(for: Self.threeByThree, newGameSeed: 0)
        #expect(session == Self.fixtureSession())
        #expect(session.highScore == 30)

        try store.save(session)
        #expect(try store.highScore(for: Self.threeByThree) == 30)
    }

    @Test func negativeStoredHighScoreCountsAsNone() throws {
        let store = GameStore(storage: Self.storage(highScores: #"{"scores":{"3x3-to64":-5},"version":1}"#))
        #expect(try store.highScore(for: Self.threeByThree) == 0)
        #expect(try store.loadSession(for: Self.threeByThree, newGameSeed: 1).highScore == 0)
    }

    @Test func variantsKeepSeparateGamesAndHighScores() throws {
        let storage = InMemoryGameStorage()
        let store = GameStore(storage: storage)
        var classic = playedGame(moves: 30).states[30]
        var fiveByFive = GameSession(rules: Self.fiveByFive, seed: 3)
        playUntilScored(&fiveByFive)
        #expect(classic.highScore != fiveByFive.highScore)

        try store.save(classic)
        try store.save(fiveByFive)

        #expect(try store.loadSession(for: .classic, newGameSeed: 0) == classic)
        #expect(try store.loadSession(for: Self.fiveByFive, newGameSeed: 0) == fiveByFive)
        #expect(try store.highScore(for: .classic) == classic.highScore)
        #expect(try store.highScore(for: Self.fiveByFive) == fiveByFive.highScore)
        #expect(storage.data(forKey: "game-classic") != nil)
        #expect(storage.data(forKey: "game-5x5") != nil)

        // Restarting one variant leaves the other alone.
        classic.restart()
        try store.save(classic)
        #expect(try store.loadSession(for: Self.fiveByFive, newGameSeed: 0) == fiveByFive)
    }

    /// High scores of a later version, after a downgrade of the app, are
    /// neither used nor overwritten.
    @Test func laterHighScoresAreKept() throws {
        let later = #"{"scores":{"3x3-to64":900,"other":800},"version":2}"#
        let storage = Self.storage(game: Self.fixture, highScores: later)
        let store = GameStore(storage: storage)

        #expect(try store.highScore(for: Self.threeByThree) == 0)
        var session = try store.loadSession(for: Self.threeByThree, newGameSeed: 0)
        #expect(session.highScore == 30, "from the saved game")
        session.redo()
        try store.save(session)

        #expect(Self.text(storage.data(forKey: "high-scores")) == later)
        #expect(try store.loadSession(for: Self.threeByThree, newGameSeed: 0) == session)
    }

    @Test func savingKeepsOtherVariantsHighScores() throws {
        let storage = Self.storage(highScores: #"{"scores":{"3x3-to64":70,"other":800},"version":1}"#)
        let store = GameStore(storage: storage)

        try store.save(playedGame(moves: 30).states[30])

        #expect(try store.highScore(for: Self.threeByThree) == 70)
        #expect(try store.highScore(for: .classic) > 0)
        #expect(Self.text(storage.data(forKey: "high-scores"))?.contains(#""other":800"#) == true)
    }

    @Test func storageReadErrorsAreThrown() {
        let store = GameStore(storage: FailingStorage(failingKeys: nil))
        #expect(throws: FailingStorage.Failure.self) {
            try store.loadSession(for: .classic, newGameSeed: 3)
        }
        #expect(throws: FailingStorage.Failure.self) {
            try store.highScore(for: .classic)
        }
    }

    @Test func storageWriteErrorsAreThrown() {
        let store = GameStore(storage: FailingStorage(failingKeys: nil))
        #expect(throws: FailingStorage.Failure.self) {
            try store.save(GameSession(rules: .classic, seed: 3))
        }
    }

    /// When only the high scores can't be read, the game is still saved, and
    /// the high scores aren't overwritten.
    @Test func highScoresReadErrorOnSaveThrowsAfterSavingTheGame() throws {
        let storage = FailingStorage(failingKeys: ["high-scores"])
        let session = playedGame(moves: 30).states[30]

        #expect(throws: FailingStorage.Failure.self) {
            try GameStore(storage: storage).save(session)
        }

        #expect(storage.contents.data(forKey: "game-classic") != nil)
        #expect(storage.contents.data(forKey: "high-scores") == nil)
        #expect(try GameStore(storage: storage.contents).loadSession(for: .classic, newGameSeed: 0) == session)
    }
}

/// In-memory storage whose reads and writes of some keys fail.
struct FailingStorage: GameStorage {
    struct Failure: Error {}

    /// The data of the keys that don't fail.
    let contents = InMemoryGameStorage()
    /// The keys that fail, or `nil` for all keys.
    let failingKeys: Set<String>?

    func data(forKey key: String) throws -> Data? {
        if failingKeys?.contains(key) ?? true {
            throw Failure()
        }
        return contents.data(forKey: key)
    }

    func setData(_ data: Data, forKey key: String) throws {
        if failingKeys?.contains(key) ?? true {
            throw Failure()
        }
        contents.setData(data, forKey: key)
    }
}
