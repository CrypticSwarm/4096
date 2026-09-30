import CoreGraphics
import GameCore
import SwiftUI
import Testing

@testable import Game4096

struct SwipeInputTests {
    @Test(arguments: [
        (CGSize(width: 40, height: 0), Direction.right),
        (CGSize(width: -40, height: 0), .left),
        (CGSize(width: 0, height: 40), .down),
        (CGSize(width: 0, height: -40), .up),
        // The dominant axis wins, even for nearly diagonal drags.
        (CGSize(width: 60, height: -59), .right),
        (CGSize(width: -30, height: 31), .down),
        // Exactly the minimum distance counts.
        (CGSize(width: -SwipeInput.minimumDistance, height: 5), .left),
    ])
    func dragsMapToTheirDominantAxis(translation: CGSize, direction: Direction) {
        #expect(SwipeInput.direction(of: translation) == direction)
    }

    @Test(arguments: [
        CGSize.zero,
        CGSize(width: SwipeInput.minimumDistance - 1, height: 0),
        CGSize(width: 10, height: -12),
    ])
    func shortDragsAreIgnored(translation: CGSize) {
        #expect(SwipeInput.direction(of: translation) == nil)
    }

    @Test func arrowKeysMapToDirections() {
        #expect(SwipeInput.direction(of: .upArrow) == .up)
        #expect(SwipeInput.direction(of: .downArrow) == .down)
        #expect(SwipeInput.direction(of: .leftArrow) == .left)
        #expect(SwipeInput.direction(of: .rightArrow) == .right)
        #expect(SwipeInput.direction(of: .space) == nil)
        #expect(SwipeInput.direction(of: KeyEquivalent("a")) == nil)
    }
}
