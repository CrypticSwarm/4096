import GameCore
import XCTest

/// Screenshots of every tile value, to review the palette and how large
/// numbers fit, on the classic board and on a 5×5 board. Each board has an
/// empty cell, so the game over message doesn't cover it.
final class TileGalleryUITests: GameUITestCase {
    func testGallery4x4() throws {
        let fixture = "0,4,8,16;32,64,128,256;512,1024,2048,4096;8192,16384,32768,65536"
        launch(LaunchConfiguration(seed: 1, board: try Board(notation: fixture)))
        assertBoard(fixture)
        // A board with a winning tile starts as just won.
        tapKeepPlaying()
        XCTAssertEqual(cell(row: 3, column: 3).label, "65536")
        XCTAssertFalse(gameOverMessage.exists)
        attachScreenshot(named: "gallery-4x4")
    }

    func testGallery5x5() throws {
        let fixture =
            "2,4,8,16,32;64,128,256,512,1024;2048,4096,8192,16384,32768;"
            + "65536,131072,262144,524288,1048576;0,0,0,0,0"
        launch(LaunchConfiguration(seed: 1, board: try Board(notation: fixture)))
        assertBoard(fixture)
        // A board with a winning tile starts as just won.
        tapKeepPlaying()
        XCTAssertEqual(cell(row: 3, column: 1).label, "131072")
        XCTAssertEqual(cell(row: 4, column: 0).label, "Empty")
        XCTAssertFalse(gameOverMessage.exists)
        attachScreenshot(named: "gallery-5x5")

        // A new game keeps the board size: the seed's first 5×5 starting board.
        tapNewGame(confirm: true)
        let configuration = LaunchConfiguration(seed: 1, board: try Board(notation: fixture))
        var generator = SplitMix64(seed: 1)
        assertBoard(configuration.rules.startingBoard(using: &generator).notation)
    }
}
