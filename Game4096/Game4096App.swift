import Foundation
import GameCore
import SwiftUI

@main
struct Game4096App: App {
    @State private var model: GameModel = {
        let configuration = LaunchConfiguration.fromProcessArguments()
        return GameModel(configuration: configuration, storage: configuration.storage.gameStorage())
    }()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.retryLoadingIfNeeded()
            // Every change is saved as it happens; this retries a failed save.
            case .background: model.saveIfNeeded()
            default: break
            }
        }
    }
}

extension LaunchConfiguration {
    /// The configuration from this process's launch arguments.
    ///
    /// Only UI tests and developers pass these arguments, so invalid ones stop
    /// the app with a message rather than being ignored.
    fileprivate static func fromProcessArguments() -> LaunchConfiguration {
        do {
            return try LaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)
        } catch {
            fatalError("Invalid launch arguments: \(error)")
        }
    }
}

extension LaunchConfiguration.Storage {
    /// The storage this option selects: files in a folder of Application
    /// Support (backed up with the device), or memory.
    fileprivate func gameStorage() -> any GameStorage {
        switch self {
        case .folder(let name):
            FileGameStorage(
                directory: URL.applicationSupportDirectory.appending(path: name, directoryHint: .isDirectory))
        case .memory:
            InMemoryGameStorage()
        }
    }
}
