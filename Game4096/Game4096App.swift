import Foundation
import GameCore
import SwiftUI

@main
struct Game4096App: App {
    @State private var model = GameModel(configuration: .fromProcessArguments())

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
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
