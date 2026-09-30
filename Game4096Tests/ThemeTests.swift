import SwiftUI
import Testing
import UIKit

@testable import Game4096

@MainActor
struct ThemeTests {
    /// Tile values from 2 through 2^20.
    static let values = (1...20).map { 1 << $0 }

    @Test func classicTilesKeepTheOriginalColors() {
        #expect(resolved(Theme.tileStyle(for: 2).background) == resolved(Color(hex: 0xEEE4DA)))
        #expect(resolved(Theme.tileStyle(for: 2048).background) == resolved(Color(hex: 0xEDC22E)))
        #expect(resolved(Theme.tileStyle(for: 4).foreground) == resolved(Theme.darkText))
        #expect(resolved(Theme.tileStyle(for: 8).foreground) == resolved(Theme.lightText))
    }

    @Test func everyValueThrough262144HasItsOwnColor() {
        let colors = Self.values.prefix(18).map { resolved(Theme.tileStyle(for: $0).background) }
        #expect(Set(colors).count == colors.count)
        // Larger values share the last color.
        #expect(
            resolved(Theme.tileStyle(for: 1 << 20).background) == resolved(Theme.tileStyle(for: 1 << 19).background))
    }

    @Test func increasedContrastDarkensTextOnClassicTilesOnly() {
        for value in Self.values {
            let normal = Theme.tileStyle(for: value)
            let increased = Theme.tileStyle(for: value, increasedContrast: true)
            #expect(normal.background == increased.background)
            if value <= 2048 {
                #expect(resolved(increased.foreground) == resolved(Theme.highContrastText), "\(value)")
            } else {
                #expect(increased.foreground == normal.foreground, "\(value)")
            }
        }
    }

    /// Tile numbers are large bold text, for which WCAG asks 3:1. Tiles past
    /// 2048, whose numbers get smaller, reach 4.5:1; the classic colors only
    /// reach 3:1 with Increase Contrast.
    @Test func textContrast() {
        for value in Self.values {
            let increased = Theme.tileStyle(for: value, increasedContrast: true)
            #expect(contrast(increased.foreground, increased.background) >= 3, "\(value)")
            if value > 2048 {
                let normal = Theme.tileStyle(for: value)
                #expect(contrast(normal.foreground, normal.background) >= 4.5, "\(value)")
            }
        }
    }

    @Test func onlyGoldTilesGlow() {
        #expect(Self.values.filter { Theme.tileStyle(for: $0).glow > 0 } == [128, 256, 512, 1024, 2048])
    }

    @Test func fontShrinksWithDigitsAndFits() {
        let side: CGFloat = 100
        var previous = CGFloat.infinity
        for value in Self.values {
            let size = Theme.tileFontSize(for: value, side: side)
            #expect(size <= previous, "\(value)")
            // The same font as Theme.tileFont, measured.
            let font = UIFont.systemFont(ofSize: size, weight: .bold)
            let width = (String(value) as NSString).size(withAttributes: [.font: font]).width
            #expect(width <= side * (1 - 2 * Theme.TileMetrics.textPadding), "\(value) is \(width) wide")
            previous = size
        }
        #expect(Theme.tileFontSize(for: 2, side: side) == 50)
        #expect(Theme.tileFontSize(for: 1024, side: side) == 30)
    }

    /// The WCAG contrast ratio of two colors.
    private func contrast(_ first: Color, _ second: Color) -> Double {
        func luminance(_ color: Color) -> Double {
            let resolved = resolved(color)
            return 0.2126 * Double(resolved.linearRed) + 0.7152 * Double(resolved.linearGreen)
                + 0.0722 * Double(resolved.linearBlue)
        }
        let (a, b) = (luminance(first), luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func resolved(_ color: Color) -> Color.Resolved {
        color.resolve(in: EnvironmentValues())
    }
}

struct BoardGeometryTests {
    @Test func classicProportions() {
        let geometry = BoardGeometry(size: 4, side: 500)
        #expect(abs(geometry.cellSide - 106.25) < 0.001)
        #expect(abs(geometry.gap - 15) < 0.001)
        let first = geometry.center(row: 0, column: 0)
        #expect(abs(first.x - (15 + 106.25 / 2)) < 0.001)
        #expect(first.x == first.y)
    }

    @Test(arguments: 2...8)
    func cellsFillTheBoardWithEqualGaps(size: Int) {
        let geometry = BoardGeometry(size: size, side: 360)
        let last = geometry.center(row: size - 1, column: size - 1)
        #expect(abs(last.x + geometry.cellSide / 2 + geometry.gap - 360) < 0.001)
        #expect(abs(last.y + geometry.cellSide / 2 + geometry.gap - 360) < 0.001)
        let next = geometry.center(row: 0, column: 1)
        #expect(abs(next.x - geometry.center(row: 0, column: 0).x - geometry.cellSide - geometry.gap) < 0.001)
    }
}
