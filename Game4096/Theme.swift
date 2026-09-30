import SwiftUI

/// The game's look in one place: the classic 2048 palette, board and tile
/// proportions, typography, button style and animation timing.
///
/// The palette is designed for a light page, so the app always uses the light
/// appearance (`UIUserInterfaceStyle` in project.yml) instead of adapting the
/// tile colors to dark mode.
enum Theme {
    /// The page behind the board.
    static let background = Color(hex: 0xFAF8EF)
    /// The board's frame and the gaps between cells.
    static let board = Color(hex: 0xBBADA0)
    /// An empty cell.
    static let emptyCell = Color(hex: 0xCDC1B4)
    /// Text on the page and on light tiles.
    static let darkText = Color(hex: 0x776E65)
    /// Text on dark tiles.
    static let lightText = Color(hex: 0xF9F6F2)
    /// Buttons on the page.
    static let button = Color(hex: 0x8F7A66)
    /// Text on the classic tiles (2 through 2048) when Increase Contrast is
    /// on: the original white on orange and gold is below 3:1, and its dark
    /// text on 2 and 4 below 4.5:1.
    static let highContrastText = Color(hex: 0x3C3A32)

    /// The game's title.
    static let titleFont = Font.system(size: 64, weight: .bold)

    /// How a tile of some value looks.
    struct TileStyle: Equatable {
        var background: Color
        var foreground: Color
        /// The opacity of the golden glow around tiles of 128 through 2048,
        /// as in the original; 0 for none. They also get a faint white inner
        /// edge of 0.6 times this opacity.
        var glow: Double
    }

    /// The glow color of tiles from 128 through 2048.
    static let glow = Color(hex: 0xF3D774)

    /// The style of a tile with `value`, a power of two.
    ///
    /// Tiles up to 2048 use the original game's colors. From 4096 on, each
    /// value gets its own color from purple through blue to green, all dark
    /// enough for white text, and values past 262144 share the original's
    /// dark "super" tile color.
    static func tileStyle(for value: Int, increasedContrast: Bool = false) -> TileStyle {
        let index = min(max(value.trailingZeroBitCount, 1), tilePalette.count) - 1
        let (background, lightText, glow) = tilePalette[index]
        let foreground =
            if increasedContrast && index < classicTileCount {
                highContrastText
            } else {
                lightText ? Self.lightText : darkText
            }
        return TileStyle(background: Color(hex: background), foreground: foreground, glow: glow)
    }

    /// The number of tiles with the original game's colors: 2 through 2048.
    private static let classicTileCount = 11

    /// Background, whether the text is light, and glow, for 2, 4, 8, … in order.
    private static let tilePalette: [(background: UInt32, lightText: Bool, glow: Double)] = [
        (0xEEE4DA, false, 0),  // 2
        (0xEDE0C8, false, 0),  // 4
        (0xF2B179, true, 0),  // 8
        (0xF59563, true, 0),  // 16
        (0xF67C5F, true, 0),  // 32
        (0xF65E3B, true, 0),  // 64
        (0xEDCF72, true, 0.24),  // 128
        (0xEDCC61, true, 0.32),  // 256
        (0xEDC850, true, 0.40),  // 512
        (0xEDC53F, true, 0.48),  // 1024
        (0xEDC22E, true, 0.56),  // 2048
        (0x8E4FC0, true, 0),  // 4096
        (0x7446BA, true, 0),  // 8192
        (0x5A45B5, true, 0),  // 16384
        (0x3F52B0, true, 0),  // 32768
        (0x2A64A8, true, 0),  // 65536
        (0x1C7486, true, 0),  // 131072
        (0x1B6E57, true, 0),  // 262144
        (0x3C3A32, true, 0),  // 524288 and up
    ]

    /// Tile proportions, as fractions of the tile's side.
    enum TileMetrics {
        /// The glow's blur radius and how far it extends past the tile: the
        /// original's `box-shadow: 0 0 30px 10px` on a 107 px tile.
        static let glowBlur: CGFloat = 0.14
        static let glowSpread: CGFloat = 0.09
        /// The least space beside the number.
        static let textPadding: CGFloat = 0.06
    }

    /// The font size for `value` on a tile `side` points wide.
    ///
    /// Like the original (55, 45, 35 and 30 px on a 107 px tile for one or two,
    /// three, four and five digits), the size shrinks with the digit count, so
    /// that the widest numbers still fit with a margin. Tile text scales with
    /// the tile, not with Dynamic Type: the board already fills the width.
    static func tileFontSize(for value: Int, side: CGFloat) -> CGFloat {
        let digits = String(value).count
        let scale: CGFloat =
            switch digits {
            case ...2: 0.50
            case 3: 0.42
            case 4: 0.30
            default: 1.3 / CGFloat(digits)  // 0.26 for 5 digits, 0.22 for 6, 0.19 for 7
            }
        return side * scale
    }

    /// The font of tile numbers.
    static func tileFont(size: CGFloat) -> Font {
        .system(size: size, weight: .bold)
    }

    /// Animation timing, as in the original: tiles slide for 100 ms, then new
    /// tiles appear and merged tiles pop over 200 ms.
    enum Motion {
        /// Seconds tiles take to slide.
        static let slideDuration = 0.1
        /// Seconds new tiles take to appear and merged tiles to pop.
        static let popDuration = 0.2
        static let slide = Animation.easeInOut(duration: slideDuration)
        /// Merged tiles grow from nothing, overshoot and settle.
        static let pop = Animation.spring(duration: popDuration, bounce: 0.5)
        /// Spawned tiles grow from nothing.
        static let appear = Animation.easeOut(duration: popDuration)
    }
}

/// The original's buttons: light bold text on a brown rounded rectangle, at
/// least 44 points tall.
struct GameButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.bold())
            .lineLimit(1)
            .foregroundStyle(Theme.lightText)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Theme.button, in: RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Where cells go on a board of `size` × `size` cells drawn `side` points wide.
///
/// Proportions follow the original game, whose 4×4 board is 500 px wide with
/// 15 px gaps: each gap is 15/106.25 of a cell, for every board size.
struct BoardGeometry: Equatable {
    let size: Int
    let side: CGFloat

    static let gapToCellRatio: CGFloat = 15 / 106.25

    /// The width of one cell.
    var cellSide: CGFloat {
        side / (CGFloat(size) + CGFloat(size + 1) * Self.gapToCellRatio)
    }

    /// The space around and between cells.
    var gap: CGFloat {
        cellSide * Self.gapToCellRatio
    }

    var cellCornerRadius: CGFloat {
        cellSide * 0.06
    }

    var boardCornerRadius: CGFloat {
        cellSide * 0.09
    }

    /// The center of the cell at `row` and `column`, from the board's top left.
    func center(row: Int, column: Int) -> CGPoint {
        let step = cellSide + gap
        return CGPoint(x: gap + cellSide / 2 + CGFloat(column) * step, y: gap + cellSide / 2 + CGFloat(row) * step)
    }
}

extension Color {
    /// A color from a 0xRRGGBB literal, in sRGB.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
