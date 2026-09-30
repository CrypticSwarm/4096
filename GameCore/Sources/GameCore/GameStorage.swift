import Foundation

/// Where a ``GameStore`` keeps its data: blobs of bytes saved under string
/// keys.
///
/// ``FileGameStorage`` keeps each key in a file, and ``InMemoryGameStorage``
/// keeps them in memory for tests and previews. The app can adapt another
/// store, such as `UserDefaults`, by implementing the two methods.
public protocol GameStorage: Sendable {
    /// Returns the data saved under `key`, or `nil` if there is none.
    ///
    /// - Throws: If there is data but it can't be read.
    func data(forKey key: String) throws -> Data?

    /// Saves `data` under `key`, replacing any data saved there before.
    ///
    /// The write must be atomic: if it fails or the app is terminated during
    /// it, later reads return either the old data or the new data in full.
    func setData(_ data: Data, forKey key: String) throws
}

/// Keeps each key's data in a file in a directory.
///
/// The file for a key is named after the key with `.json` appended, where
/// every character but lowercase ASCII letters, digits, `-` and `_` is
/// percent-encoded byte by byte (`"Classic/2"` is saved as
/// `%43lassic%2F2.json`). So any key maps to a single file inside the
/// directory, and distinct keys map to distinct names even on file systems
/// that ignore case.
public struct FileGameStorage: GameStorage {
    /// The directory holding the files. It is created on the first save.
    public let directory: URL

    /// Creates storage that keeps its files in `directory`, such as a
    /// subdirectory of the app's Application Support directory.
    public init(directory: URL) {
        self.directory = directory
    }

    public func data(forKey key: String) throws -> Data? {
        let url = fileURL(forKey: key)
        do {
            return try Data(contentsOf: url)
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) {
                return nil
            }
            throw error
        }
    }

    /// Writes the data to a temporary file, then moves it over the key's file.
    public func setData(_ data: Data, forKey key: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(forKey: key), options: .atomic)
    }

    /// The URL of the file that holds `key`'s data.
    func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent(Self.fileName(forKey: key), isDirectory: false)
    }

    static func fileName(forKey key: String) -> String {
        var name = ""
        for byte in key.utf8 {
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
                UInt8(ascii: "-"), UInt8(ascii: "_"):
                name.append(Character(Unicode.Scalar(byte)))
            default:
                name += (byte < 0x10 ? "%0" : "%") + String(byte, radix: 16, uppercase: true)
            }
        }
        return name + ".json"
    }
}

/// Keeps data in memory, for tests, previews and UI tests that must not
/// touch saved games. Copies share their contents.
public final class InMemoryGameStorage: GameStorage, @unchecked Sendable {
    // @unchecked: every access to `contents` holds `lock`.
    private let lock = NSLock()
    private var contents: [String: Data]

    /// Creates storage holding `contents`, keyed like ``data(forKey:)``.
    public init(_ contents: [String: Data] = [:]) {
        self.contents = contents
    }

    public func data(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return contents[key]
    }

    public func setData(_ data: Data, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        contents[key] = data
    }
}
