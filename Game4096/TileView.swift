import SwiftUI

/// One numbered tile, `side` points wide, without its glow (see ``TileGlow``).
struct TileView: View {
    let value: Int
    let side: CGFloat
    let cornerRadius: CGFloat

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let style = Theme.tileStyle(for: value, increasedContrast: contrast == .increased)
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(style.background)
            .overlay {
                if style.glow > 0 {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.white.opacity(style.glow * 0.6), lineWidth: 1)
                }
            }
            .overlay {
                Text(verbatim: String(value))
                    .font(Theme.tileFont(size: Theme.tileFontSize(for: value, side: side)))
                    .foregroundStyle(style.foreground)
                    .lineLimit(1)
                    // A safety net: the size table already fits every value.
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, side * Theme.TileMetrics.textPadding)
            }
            .frame(width: side, height: side)
    }
}

/// The golden glow around a tile of 128 through 2048, like the original's
/// `box-shadow`, and nothing for other tiles. The board draws every glow
/// below every tile, so glows only tint the board, never other tiles.
struct TileGlow: View {
    let value: Int
    let side: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        let glow = Theme.tileStyle(for: value).glow
        ZStack {
            if glow > 0 {
                let spread = side * Theme.TileMetrics.glowSpread
                RoundedRectangle(cornerRadius: cornerRadius + spread)
                    .fill(Theme.glow.opacity(glow))
                    .padding(-spread)
                    .blur(radius: side * Theme.TileMetrics.glowBlur)
            }
        }
        .frame(width: side, height: side)
    }
}

#Preview {
    VStack(spacing: 8) {
        ForEach(
            [[2, 4, 8, 16], [32, 64, 128, 256], [512, 1024, 2048, 4096], [16384, 131072, 1_048_576, 1 << 24]],
            id: \.self
        ) { row in
            HStack(spacing: 8) {
                ForEach(row, id: \.self) { TileView(value: $0, side: 80, cornerRadius: 5) }
            }
        }
    }
    .padding()
    .background(Theme.board)
}
