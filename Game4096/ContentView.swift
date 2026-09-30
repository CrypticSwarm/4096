import GameCore
import SwiftUI

/// The game screen, laid out like the original: the title and the scores at
/// the top, then the goal and New Game right above the board, and Undo and
/// Redo below it within reach of the thumb. Everything from the goal down is
/// centered in the height left under the title. Swipes anywhere on the
/// screen (or arrow keys) move the tiles.
///
/// With VoiceOver running, each change is announced (see
/// `MoveAnnouncement`).
struct ContentView: View {
    @Bindable var model: GameModel

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 16)
            goal
            board
                .padding(.top, 16)
                // Gets its full width before the spacers share what is left.
                .layoutPriority(1)
            controls
                .padding(.top, 16)
            if let problem = model.storageProblem {
                Text(Self.text(for: problem))
                    .font(.footnote)
                    .foregroundStyle(Theme.darkText)
                    .multilineTextAlignment(.center)
                    .wrapToFit()
                    .chromeTextSize()
                    .padding(.top, 8)
            }
            Spacer(minLength: 16)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onSwipe { model.perform($0) }
        .alert(AccessibilityID.newGameAlertTitle, isPresented: $model.isConfirmingNewGame) {
            Button("New Game", role: .destructive) { model.confirmNewGame() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This game will end and can't be brought back. Your best score is kept.")
        }
        .onChange(of: model.lastChange) { _, change in
            // High priority, so that VoiceOver moving its focus (for example
            // when a message or the alert goes away) doesn't cut it off.
            if voiceOverEnabled, let change {
                announce(MoveAnnouncement.text(for: change, in: model), urgently: true)
            }
        }
        .onChange(of: model.storageProblem) { _, problem in
            // Queued after the announcement of the change that caused it.
            if voiceOverEnabled, let problem {
                announce(Self.text(for: problem), urgently: false)
            }
        }
    }

    /// The title with the scores beside it, or below it when they don't fit
    /// (large scores or large text).
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                title
                Spacer(minLength: 0)
                scores
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                title
                scores
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .chromeTextSize()
    }

    private var title: some View {
        Text(GameInfo.title)
            .font(Theme.titleFont)
            .foregroundStyle(Theme.darkText)
            .fitOnOneLine()
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(AccessibilityID.title)
    }

    private var scores: some View {
        HStack(spacing: 6) {
            ScoreBox(title: "SCORE", accessibilityName: "Score", value: model.score, change: model.lastChange)
                .accessibilityIdentifier(AccessibilityID.score)
            ScoreBox(title: "BEST", accessibilityName: "Best score", value: model.highScore)
                .accessibilityIdentifier(AccessibilityID.best)
        }
    }

    /// The goal and New Game, as in the original's row above the board.
    private var goal: some View {
        HStack(spacing: 8) {
            Text("Join the tiles, get to \(Text(verbatim: "\(model.winningValue)!").bold())")
                .font(.subheadline)
                .foregroundStyle(Theme.darkText)
                .wrapToFit()
            Spacer(minLength: 0)
            Button("New Game") { model.requestNewGame() }
                .buttonStyle(GameButtonStyle())
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier(AccessibilityID.newGame)
                .fixedSize()
        }
        .chromeTextSize()
    }

    private var board: some View {
        BoardView(layout: model.layout) { model.perform($0) }
            .overlay {
                if let overlay = model.overlay {
                    GameMessageView(
                        overlay: overlay,
                        boardSize: model.layout.board.size,
                        winningValue: model.winningValue,
                        canUndo: model.canUndo,
                        onKeepPlaying: { model.keepPlaying() },
                        onNewGame: { model.requestNewGame() }
                    )
                    // Each message comes and goes on its own, also when Keep
                    // playing reveals that the game is over.
                    .id(overlay)
                    .transition(.gameMessage(reduceMotion: reduceMotion))
                }
            }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                model.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!model.canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .accessibilityHint("Takes back your last move. Up to \(GameSession.undoLimit) moves can be taken back.")
            .accessibilityIdentifier(AccessibilityID.undo)

            Button {
                model.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!model.canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .accessibilityHint("Plays the move you took back again, with the same new tile.")
            .accessibilityIdentifier(AccessibilityID.redo)
        }
        .buttonStyle(GameButtonStyle())
        .chromeTextSize()
    }

    /// Posts `text` for VoiceOver: urgently, with high priority, which
    /// nothing interrupts, or else with low priority, after other speech.
    private func announce(_ text: String, urgently: Bool) {
        var announcement = AttributedString(text)
        announcement.accessibilitySpeechAnnouncementPriority = urgently ? .high : .low
        AccessibilityNotification.Announcement(announcement).post()
    }

    private static func text(for problem: GameModel.StorageProblem) -> String {
        switch problem {
        case .couldNotLoad: "Your saved game couldn't be opened, so this game won't be saved."
        case .couldNotSave: "The game couldn't be saved. It will try again after your next change."
        }
    }
}

#Preview {
    ContentView(model: GameModel(configuration: LaunchConfiguration(seed: 1), storage: InMemoryGameStorage()))
}

#Preview("Game over") {
    ContentView(
        model: GameModel(
            configuration: LaunchConfiguration(
                seed: 1, board: try! Board(notation: "2,4,2,4;4,2,4,2;2,4,2,4;4,2,4,2"), score: 1234),
            storage: InMemoryGameStorage()))
}
