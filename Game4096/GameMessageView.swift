import GameCore
import SwiftUI

/// The message over the board after a win or when the game is over, like
/// the original's: a translucent layer with a large title and buttons. It
/// fades in once the last move's tiles have settled.
///
/// The win message is modal for VoiceOver, since moves wait until the
/// player chooses, and Return keeps playing. The game over message isn't
/// modal, so Undo stays reachable. The change that shows a message announces
/// it (see `MoveAnnouncement`).
struct GameMessageView: View {
    let overlay: GameModel.Overlay
    /// The board's size in cells, for its corner radius.
    let boardSize: Int
    let winningValue: Int
    let canUndo: Bool
    let onKeepPlaying: () -> Void
    let onNewGame: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { proxy in
            let cornerRadius = BoardGeometry(size: boardSize, side: proxy.size.width).boardCornerRadius
            VStack(spacing: 16) {
                Text(overlay.title)
                    .font(Theme.messageTitleFont)
                    .fitOnOneLine()
                    .accessibilityAddTraits(.isHeader)
                Text(overlay.detail(winningValue: winningValue, canUndo: canUndo))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .wrapToFit(maxLines: 4)
                // Side by side if they fit, otherwise stacked.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { buttons }
                    VStack(spacing: 12) { buttons }
                }
                .buttonStyle(GameButtonStyle())
            }
            .foregroundStyle(textColor)
            .padding(16)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(background, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
        .chromeTextSize()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(overlay == .win ? AccessibilityID.winMessage : AccessibilityID.gameOverMessage)
        .accessibilityAddTraits(overlay == .win ? .isModal : [])
    }

    @ViewBuilder private var buttons: some View {
        if overlay == .win {
            Button("Keep playing", action: onKeepPlaying)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(AccessibilityID.keepPlaying)
        }
        Button("New Game", action: onNewGame)
            .accessibilityIdentifier(AccessibilityID.messageNewGame)
    }

    private var increasedContrast: Bool {
        contrast == .increased
    }

    private var textColor: Color {
        switch overlay {
        case .win: Theme.lightText
        case .gameOver: increasedContrast ? Theme.highContrastText : Theme.darkText
        }
    }

    private var background: Color {
        switch overlay {
        case .win: Theme.winMessageBackground(winningValue: winningValue, increasedContrast: increasedContrast)
        case .gameOver: Theme.gameOverMessageBackground(increasedContrast: increasedContrast)
        }
    }
}

extension AnyTransition {
    /// How ``GameMessageView`` comes and goes: it fades in once the last
    /// move's tiles have slid and popped, plus a moment to see the board,
    /// and fades out quickly. With Reduce Motion it fades in at once.
    static func gameMessage(reduceMotion: Bool) -> AnyTransition {
        let delay = reduceMotion ? 0 : Theme.Motion.slideDuration + Theme.Motion.popDuration + 0.3
        return .asymmetric(
            insertion: .opacity.animation(.easeIn(duration: 0.4).delay(delay)),
            removal: .opacity.animation(.easeOut(duration: 0.15)))
    }
}

#Preview("Win") {
    GameMessageView(
        overlay: .win, boardSize: 4, winningValue: 4096, canUndo: true, onKeepPlaying: {}, onNewGame: {}
    )
    .frame(width: 360, height: 360)
    .background(Theme.board)
}

#Preview("Game over") {
    GameMessageView(
        overlay: .gameOver, boardSize: 4, winningValue: 4096, canUndo: true, onKeepPlaying: {}, onNewGame: {}
    )
    .frame(width: 360, height: 360)
    .background(Theme.board)
}
