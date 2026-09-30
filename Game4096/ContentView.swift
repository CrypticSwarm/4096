import GameCore
import SwiftUI

/// Placeholder root view; replaced by the game screen in a later change.
struct ContentView: View {
    var body: some View {
        Text(GameInfo.title)
            .font(.system(size: 64, weight: .bold, design: .rounded))
            .accessibilityIdentifier(AccessibilityID.title)
    }
}

#Preview {
    ContentView()
}
