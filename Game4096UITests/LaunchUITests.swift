import GameCore
import XCTest

final class LaunchUITests: GameUITestCase {
    /// Without a saved game, the app starts a new game from the seed, with
    /// nothing to undo or redo.
    func testLaunchShowsTitleAndTheSeedsStartingBoard() {
        launch(LaunchConfiguration(seed: 2026))
        XCTAssertTrue(app.staticTexts[AccessibilityID.title].exists)
        // Written out, not from launchGame, to check the app's choice of game.
        assertShows(GameSession(rules: .classic, seed: 2026))
        XCTAssertTrue(newGameButton.isEnabled)
        attachScreenshot(named: "launch")
    }

    /// The largest text size, with a large best score: the header's parts
    /// must all show, without overlapping.
    func testLargeText() {
        launch(
            LaunchConfiguration(seed: 2026, highScore: 204_800),
            extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertEqual(bestBox.value as? String, "204800")
        let window = app.windows.firstMatch.frame
        let parts = [app.staticTexts[AccessibilityID.title], scoreBox, bestBox, newGameButton, undoButton, board]
        let frames = parts.map { $0.frame }
        for (index, frame) in frames.enumerated() {
            XCTAssertTrue(window.contains(frame), "\(parts[index].identifier) is off screen: \(frame)")
            for other in frames[(index + 1)...] {
                XCTAssertFalse(frame.intersects(other), "\(parts[index].identifier) overlaps: \(frame), \(other)")
            }
        }
        XCTAssertTrue(newGameButton.isHittable)
        attachScreenshot(named: "launch-large-text")
    }
}
