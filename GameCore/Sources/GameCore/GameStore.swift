import Foundation

/// Saves and restores games in progress and high scores.
///
/// Each variant has its own saved game, so switching variants doesn't lose a
/// game, and high scores are kept apart from games, so they survive a new
/// game or a saved game that can't be read.
///
///     let store = GameStore(storage: FileGameStorage(directory: savesURL))
///     var session = store.loadSession(for: .classic, newGameSeed: .random(in: .min ... .max))
///     session.move(.left)
///     try store.save(session)
///
/// ## Format
///
/// The data is JSON with sorted keys, saved under these keys of the
/// ``GameStorage``:
///
/// - `game-<rules id>`: `{"version": 1, "session": <session>}`, where
///   `<session>` is the ``GameSession`` encoding, including its rules.
/// - `high-scores`: `{"version": 1, "scores": {"<rules id>": <score>, ...}}`.
///
/// Data that can't be read, is inconsistent or has another version is
/// ignored: loading starts a new game instead, and a new save replaces it.
///
/// ## Changing the format
///
/// Keep the meaning of an existing version unchanged. When the format must
/// change, raise ``formatVersion``, keep a frozen copy of the types that
/// decode the old version, and convert old data when loading, so that saves
/// from earlier app versions still load. Saves from a later version than the
/// app knows (after a downgrade) are ignored.
public struct GameStore: Sendable {
    /// The version of the format this store writes.
    public static let formatVersion = 1

    private let storage: any GameStorage

    /// Creates a store that keeps its data in `storage`.
    public init(storage: any GameStorage) {
        self.storage = storage
    }

    /// Returns the saved game of the variant `rules` describe, or a new game
    /// if there is none or it can't be restored.
    ///
    /// A saved game is restored only if it was saved with the same rules. In
    /// either case the session's high score is the best of the saved game's
    /// and the stored high score.
    ///
    /// - Parameter newGameSeed: Seeds the new game, if one is needed.
    public func loadSession(for rules: GameRules, newGameSeed: UInt64) -> GameSession {
        let highScore = highScore(for: rules)
        guard var session = try? savedSession(for: rules) else {
            return GameSession(rules: rules, seed: newGameSeed, highScore: highScore)
        }
        session.raiseHighScore(to: highScore)
        return session
    }

    /// Saves `session` as its variant's game in progress, replacing the one
    /// saved before, and raises the variant's stored high score to the
    /// session's.
    ///
    /// Call it after every change the player shouldn't lose, such as each
    /// move, undo, redo and restart, or at least when the app moves to the
    /// background.
    ///
    /// - Throws: If the storage fails. The game is saved first, so if only the
    ///   high score fails to save, it is recovered from the game on the next
    ///   load.
    public func save(_ session: GameSession) throws {
        try storage.setData(
            Self.encode(SavedGame(version: Self.formatVersion, session: session)),
            forKey: Self.gameKey(for: session.rules))
        var scores = loadHighScores()
        if session.highScore > scores[session.rules.id, default: 0] {
            scores[session.rules.id] = session.highScore
            try storage.setData(
                Self.encode(SavedHighScores(version: Self.formatVersion, scores: scores)), forKey: Self.highScoresKey)
        }
    }

    /// The stored high score of the variant `rules` describe, or 0 if there
    /// is none or the high scores can't be read.
    public func highScore(for rules: GameRules) -> Int {
        max(0, loadHighScores()[rules.id, default: 0])
    }

    static let highScoresKey = "high-scores"

    static func gameKey(for rules: GameRules) -> String {
        "game-" + rules.id
    }

    /// The saved game of the variant, or `nil` if there is none.
    ///
    /// - Throws: If the data can't be read, has an unknown version or doesn't
    ///   decode to a consistent game with these rules.
    func savedSession(for rules: GameRules) throws -> GameSession? {
        guard let data = try storage.data(forKey: Self.gameKey(for: rules)) else { return nil }
        let session = try Self.decode(SavedGame.self, from: data).session
        guard session.rules == rules else { throw GameStoreError.rulesChanged }
        return session
    }

    /// The stored high scores by rules id, empty if they can't be read.
    private func loadHighScores() -> [String: Int] {
        guard let data = try? storage.data(forKey: Self.highScoresKey),
            let saved = try? Self.decode(SavedHighScores.self, from: data)
        else { return [:] }
        return saved.scores
    }

    private static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    /// Decodes `data` after checking that it has the current version.
    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        let version = try decoder.decode(VersionHeader.self, from: data).version
        guard version == formatVersion else { throw GameStoreError.unsupportedVersion(version) }
        return try decoder.decode(type, from: data)
    }
}

/// Why saved data wasn't restored.
enum GameStoreError: Error {
    case unsupportedVersion(Int)
    case rulesChanged
}

/// The part of every saved value that says how to decode the rest.
private struct VersionHeader: Decodable {
    let version: Int
}

private struct SavedGame: Codable {
    let version: Int
    let session: GameSession
}

private struct SavedHighScores: Codable {
    let version: Int
    let scores: [String: Int]
}
