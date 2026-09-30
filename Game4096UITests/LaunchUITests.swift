import GameCore
import XCTest

final class LaunchUITests: GameUITestCase {
    func testLaunchShowsTitleAndTheSeedsStartingBoard() {
        launch(LaunchConfiguration(seed: 2026))
        XCTAssertTrue(app.staticTexts[AccessibilityID.title].exists)
        var generator = SplitMix64(seed: 2026)
        assertBoard(GameRules.classic.startingBoard(using: &generator).notation)
        attachScreenshot(named: "launch")
    }
}
