import SwiftUI

/// A score in the original's style: a small uppercase name over the number,
/// in a box the color of the board. When `change` scored points, a "+N"
/// floats up from the box and fades, as in the original.
///
/// For accessibility the box is one element labeled `accessibilityName`,
/// whose value is the number.
struct ScoreBox: View {
    let title: String
    let accessibilityName: String
    let value: Int
    var change: GameModel.Change?

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption.bold())
                .fitOnOneLine()
                .foregroundStyle(contrast == .increased ? Theme.lightText : Theme.scoreLabel)
            Text(verbatim: String(value))
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(.white)
                .fitOnOneLine()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minWidth: 72)
        .background(
            contrast == .increased ? Theme.highContrastScoreBox : Theme.scoreBox,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay {
            if let change, change.points > 0 {
                ScoreGainView(points: change.points)
                    .id(change.id)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(Text(verbatim: String(value)))
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityShowsLargeContentViewer {
            Text(verbatim: "\(title) \(value)")
        }
    }
}

/// "+N" rising from the score and fading over 600 ms, like the original's
/// score addition; with Reduce Motion it only fades.
private struct ScoreGainView: View {
    let points: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasRisen = false

    var body: some View {
        Text(verbatim: "+\(points)")
            .font(.title2.bold())
            .foregroundStyle(Theme.scoreGain)
            .lineLimit(1)
            .fixedSize()
            .offset(y: hasRisen && !reduceMotion ? -60 : 0)
            .opacity(hasRisen ? 0 : 1)
            .onAppear {
                withAnimation(.easeIn(duration: 0.6)) { hasRisen = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        ScoreBox(title: "SCORE", accessibilityName: "Score", value: 1234)
        ScoreBox(title: "BEST", accessibilityName: "Best score", value: 123_456)
    }
    .padding()
    .background(Theme.background)
}
