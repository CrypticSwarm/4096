import Foundation

/// Saves and restores games in progress and high scores.
///
/// Each variant has its own saved game, so switching variants doesn't lose a
/// game, and high scores are kept apart from games, so they survive a new
/// game or a saved game that can't be restored.
///
///     let store = GameStore(storage: FileGameStorage(directory: savesURL))
///     var session = try store.loadSession(for: .classic, newGameSeed: .random(in: .min ... .max))
///     session.move(.left)
///     try store.save(session)
///
/// Use a store from one place at a time, such as the main actor: saving
/// reads, updates and writes back the high scores.
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
/// Each has its own version. A saved game that can't be decoded, isn't a
/// consistent game, was saved with other rules or has another version is
/// ignored: loading starts a new game, and the next save replaces it. High
/// scores that can't be decoded are replaced on the next save too, but high
/// scores of a later version (after a downgrade of the app) are kept and not
/// updated; each saved game still carries its variant's high score.
///
/// ## Changing the format
///
/// Keep the meaning of an existing version unchanged; the pinned fixtures in
/// the tests guard it. When a format must change, raise its version, keep a
/// frozen copy of the types that decode the old version, and convert old data
/// when loading, so that saves from earlier app versions still load.
public struct GameStore: Sendable {
    /// The version of the saved game format this store reads and writes.
    static let gameVersion = 1
    /// The version of the high scores format this store reads and writes.
    static let highScoresVersion = 1
    /// Legitimate data is a few kilobytes; anything much larger is rejected
    /// without decoding it.
    static let maxDataSize = 1 << 20

    private let storage: any GameStorage

    /// Creates a store that keeps its data in `storage`.
    public init(storage: any GameStorage) {
        self.storage = storage
    }

    /// Returns the saved game of the variant `rules` describe, or a new game
    /// if there is none or it can't be restored.
    ///
    /// A saved game is restored only if it was saved with the same rules, and
    /// its high score is raised to the stored one if that is higher. A new
    /// game starts with the stored high score.
    ///
    /// - Parameter newGameSeed: Seeds the new game, if one is needed.
    /// - Throws: If the storage fails to read, which may be temporary: the app
    ///   shouldn't save over the game it couldn't read.
    public func loadSession(for rules: GameRules, newGameSeed: UInt64) throws -> GameSession {
        let highScore = try highScore(for: rules)
        guard let data = try storage.data(forKey: Self.gameKey(for: rules)),
            case .current(let saved) = Self.decode(SavedGame.self, from: data, version: Self.gameVersion),
            saved.session.rules == rules
        else { return GameSession(rules: rules, seed: newGameSeed, highScore: highScore) }
        var session = saved.session
        session.raiseHighScore(to: highScore)
        return session
    }

    /// Saves `session` as its variant's game in progress, replacing the one
    /// saved before, and raises the variant's stored high score to the
    /// session's.
    ///
    /// Call it after every change the player shouldn't lose: each move, undo,
    /// redo, restart and ``GameSession/acknowledgeWin()``, or at least when
    /// the app moves to the background.
    ///
    /// - Throws: If the storage fails. The game is saved first, so if only the
    ///   high score fails to save, it is recovered from the game on the next
    ///   load.
    public func save(_ session: GameSession) throws {
        try storage.setData(
            Self.encode(SavedGame(version: Self.gameVersion, session: session)),
            forKey: Self.gameKey(for: session.rules))

        var scores: [String: Int] = [:]
        if let data = try storage.data(forKey: Self.highScoresKey) {
            switch Self.decode(SavedHighScores.self, from: data, version: Self.highScoresVersion) {
            case .current(let saved): scores = saved.scores
            case .later: return
            case .unusable: break
            }
        }
        guard session.highScore > scores[session.rules.id, default: 0] else { return }
        scores[session.rules.id] = session.highScore
        try storage.setData(
            Self.encode(SavedHighScores(version: Self.highScoresVersion, scores: scores)), forKey: Self.highScoresKey)
    }

    /// The stored high score of the variant `rules` describe, or 0 if there
    /// is none, or the high scores can't be decoded or have a later version.
    ///
    /// - Throws: If the storage fails to read.
    public func highScore(for rules: GameRules) throws -> Int {
        guard let data = try storage.data(forKey: Self.highScoresKey),
            case .current(let saved) = Self.decode(SavedHighScores.self, from: data, version: Self.highScoresVersion)
        else { return 0 }
        return max(0, saved.scores[rules.id, default: 0])
    }

    private static let highScoresKey = "high-scores"

    private static func gameKey(for rules: GameRules) -> String {
        "game-" + rules.id
    }

    private static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    /// Decodes `data` if it has the given version.
    private static func decode<Value: Decodable>(
        _ type: Value.Type, from data: Data, version: Int
    ) -> Decoded<Value> {
        let decoder = JSONDecoder()
        guard data.count <= maxDataSize, let header = try? decoder.decode(VersionHeader.self, from: data) else {
            return .unusable
        }
        if header.version > version {
            return .later
        }
        guard header.version == version, let value = try? decoder.decode(type, from: data) else { return .unusable }
        return .current(value)
    }
}

/// The outcome of decoding saved data.
private enum Decoded<Value> {
    /// The data has the current version and decodes to `Value`.
    case current(Value)
    /// The data has a later version than this app knows.
    case later
    /// The data doesn't decode.
    case unusable
}

/// The part of all saved data that says how to decode the rest.
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
