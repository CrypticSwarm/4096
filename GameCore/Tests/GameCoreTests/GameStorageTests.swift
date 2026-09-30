import Foundation
import GameCore
import Testing

final class GameStorageTests {
    /// A new temporary directory that doesn't exist yet; the test's
    /// ``deinit`` removes it.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("GameStorageTests-\(UUID().uuidString)", isDirectory: true)

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func fileNames(in directory: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }

    @Test func inMemoryStorageKeepsDataByKey() {
        let storage = InMemoryGameStorage(["a": Data([1])])
        #expect(storage.data(forKey: "a") == Data([1]))
        #expect(storage.data(forKey: "b") == nil)
        storage.setData(Data([2]), forKey: "a")
        storage.setData(Data([3]), forKey: "b")
        #expect(storage.data(forKey: "a") == Data([2]))
        #expect(storage.data(forKey: "b") == Data([3]))
    }

    @Test func fileStorageReadsNothingBeforeTheFirstSave() throws {
        let storage = FileGameStorage(directory: directory.appendingPathComponent("saves", isDirectory: true))
        #expect(try storage.data(forKey: "game-classic") == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path), "reading creates nothing")
    }

    @Test func fileStorageCreatesItsDirectoryAndReplacesFiles() throws {
        let saves = directory.appendingPathComponent("a/b/saves", isDirectory: true)
        let storage = FileGameStorage(directory: saves)

        try storage.setData(Data("first".utf8), forKey: "game-classic")
        try storage.setData(Data("second, longer".utf8), forKey: "game-classic")
        try storage.setData(Data("third".utf8), forKey: "game-classic")
        try storage.setData(Data("scores".utf8), forKey: "high-scores")

        #expect(try storage.data(forKey: "game-classic") == Data("third".utf8))
        #expect(try storage.data(forKey: "high-scores") == Data("scores".utf8))
        #expect(try fileNames(in: saves) == ["game-classic.json", "high-scores.json"], "no temporary files left")
        // A new instance on the same directory reads the same data.
        #expect(try FileGameStorage(directory: saves).data(forKey: "game-classic") == Data("third".utf8))
    }

    @Test func fileNamesEscapeKeys() throws {
        let storage = FileGameStorage(directory: directory)
        let keys = ["game-classic_2", "Classic", "classic", "../up", "a/b", "é", "tab\t", ""]
        for (index, key) in keys.enumerated() {
            try storage.setData(Data([UInt8(index)]), forKey: key)
        }
        for (index, key) in keys.enumerated() {
            #expect(try storage.data(forKey: key) == Data([UInt8(index)]), "\(key)")
        }
        #expect(
            try fileNames(in: directory) == [
                "game-classic_2.json", "%43lassic.json", "classic.json", "%2E%2E%2Fup.json", "a%2Fb.json",
                "%C3%A9.json", "tab%09.json", ".json",
            ])
    }

    @Test func unreadableFileThrows() throws {
        // A directory where the file should be can't be read as data.
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("game-classic.json"), withIntermediateDirectories: true)
        let storage = FileGameStorage(directory: directory)

        #expect(throws: (any Error).self) { try storage.data(forKey: "game-classic") }
        #expect(throws: (any Error).self) { try storage.setData(Data(), forKey: "game-classic") }
        let store = GameStore(storage: storage)
        #expect(store.loadSession(for: .classic, newGameSeed: 1) == GameSession(rules: .classic, seed: 1))
    }

    @Test func unwritableDirectoryThrows() throws {
        // A file where the directory should be.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("saves")
        try Data().write(to: file)

        #expect(throws: (any Error).self) {
            try FileGameStorage(directory: file).setData(Data([1]), forKey: "game-classic")
        }
    }

    @Test func storeRoundTripsThroughFiles() throws {
        let session = GameSessionCodingTests.midGame()
        try GameStore(storage: FileGameStorage(directory: directory)).save(session)

        let store = GameStore(storage: FileGameStorage(directory: directory))
        #expect(store.loadSession(for: .classic, newGameSeed: 0) == session)
        #expect(store.highScore(for: .classic) == session.highScore)
    }
}
