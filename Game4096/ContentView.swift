import GameCore
import SwiftUI

/// The game screen: the title, a new game button and the board. Swipes
/// anywhere on the screen (or arrow keys) move the tiles.
struct ContentView: View {
    let model: GameModel

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                Text(GameInfo.title)
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.darkText)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(AccessibilityID.title)
                Spacer()
                Button("New Game") { model.newGame() }
                    .buttonStyle(GameButtonStyle())
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityIdentifier(AccessibilityID.newGame)
            }
            BoardView(layout: model.layout) { model.perform($0) }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onSwipe { model.perform($0) }
    }
}

#Preview {
    ContentView(model: GameModel(configuration: LaunchConfiguration(seed: 1)))
}
