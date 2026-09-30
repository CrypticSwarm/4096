import GameCore
import XCTest

/// Plays seeded games through the UI and checks the exact boards.
///
/// The expected boards include the tile that spawns after each move, which
/// the seed determines (see `seedProducesAKnownGame` in the GameCore tests:
/// if a toolchain update changes seeded games, these expectations change
/// too).
final class BoardUITests: GameUITestCase {
    /// Up changes nothing on this board; every other direction merges.
    static let fixture = "2,2,4,8;4,8,2,0;0,0,0,0;0,0,0,0"
    static let seed: UInt64 = 42

    /// The boards after swiping left, down, right and up from ``fixture``.
    static let expectedMoves: [(direction: Direction, board: String)] = [
        (.left, "4,4,8,0;4,8,2,0;0,0,0,0;0,2,0,0"),
        (.down, "0,0,2,0;0,4,0,0;0,8,8,0;8,2,2,0"),
        (.right, "2,0,0,2;0,0,0,4;0,0,0,16;0,0,8,4"),
        (.up, "2,0,8,2;0,2,0,4;0,0,0,16;0,0,0,4"),
    ]

    func testSwipesInEveryDirection() throws {
        launch(LaunchConfiguration(seed: Self.seed, board: try Board(notation: Self.fixture)))
        assertBoard(Self.fixture)
        attachScreenshot(named: "board-0-fixture")

        swipe(.up)
        settle()
        assertBoard(Self.fixture, "A swipe that changes nothing must not spawn a tile")

        for (index, (direction, expected)) in Self.expectedMoves.enumerated() {
            swipe(direction)
            assertBoard(expected, "after swiping \(direction)")
            attachScreenshot(named: "board-\(index + 1)-after-\(direction)")
        }
        XCTAssertEqual(cell(row: 2, column: 3).label, "16")
        XCTAssertEqual(cell(row: 2, column: 0).label, "Empty")
    }

    /// Swipes in quick succession must each play a move. (The drawn tiles
    /// can't be read through accessibility; TileAnimationTests covers how an
    /// animation that is cut short catches up.)
    func testQuickSwipesPlayEveryMove() throws {
        launch(LaunchConfiguration(seed: Self.seed, board: try Board(notation: Self.fixture)))
        for (direction, _) in Self.expectedMoves {
            swipe(direction)
        }
        assertBoard(Self.expectedMoves.last!.board)
        attachScreenshot(named: "board-quick-swipes")
    }

    func testNewGameStartsFromTheSeed() throws {
        launch(LaunchConfiguration(seed: Self.seed, board: try Board(notation: Self.fixture)))
        app.buttons[AccessibilityID.newGame].tap()
        // The fixture board used no random numbers, so the new game is the
        // seed's first starting board.
        var generator = SplitMix64(seed: Self.seed)
        assertBoard(GameRules.classic.startingBoard(using: &generator).notation)
    }

    /// Each cell is its own accessibility element with the cell's frame, so
    /// VoiceOver can find cells by touch.
    func testCellsAreSeparateElements() throws {
        launch(LaunchConfiguration(seed: Self.seed, board: try Board(notation: Self.fixture)))
        let boardFrame = board.frame
        let first = cell(row: 0, column: 0).frame
        let last = cell(row: 3, column: 3).frame
        XCTAssertLessThan(first.width, boardFrame.width / 4)
        XCTAssertLessThan(first.maxX, last.minX)
        XCTAssertLessThan(first.maxY, last.minY)
        XCTAssertTrue(boardFrame.contains(first) && boardFrame.contains(last))
        XCTAssertEqual(cell(row: 0, column: 3).label, "8")
    }

    /// Apple's automated accessibility checks. Contrast and Dynamic Type are
    /// deliberate exceptions: the classic tile colors are kept (Increase
    /// Contrast fixes them), and tile numbers scale with the tile.
    func testAccessibilityAudit() throws {
        launch(LaunchConfiguration(seed: Self.seed, board: try Board(notation: Self.fixture)))
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting([.contrast, .dynamicType]))
    }
}
