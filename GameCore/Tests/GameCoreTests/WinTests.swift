import GameCore
import Testing

struct WinTests {
    /// A 3×3 variant won by an 8 tile.
    static let toEight = GameRules(id: "to8", boardSize: 3, winningValue: 8)
    /// Sliding left makes an 8.
    static let oneMergeFromEight = [[4, 4, 0], [0, 0, 0], [0, 0, 0]]
    /// Under rules won by a 64, sliding left wins and leaves one free cell,
    /// where a 2 or a 4 matches nothing around it: the move also ends the game.
    static let winsAndEnds = [[32, 32, 16], [2, 4, 8], [4, 2, 4]]

    static func session(_ rows: [[Int]], seed: UInt64 = 1) throws -> GameSession {
        GameSession(rules: toEight, board: try Board(rows: rows), seed: seed)
    }

    @Test func newGameHasNotWon() {
        let session = GameSession(rules: .classic, seed: 1)
        #expect(!session.hasWon)
        #expect(!session.shouldPresentWin)
    }

    @Test func reachingTheWinningTilePresentsTheWin() throws {
        var session = try Self.session(Self.oneMergeFromEight)
        #expect(!session.hasWon)

        session.move(.left)

        #expect(session.board.highestTileValue == 8)
        #expect(session.hasWon)
        #expect(session.shouldPresentWin)
        #expect(!session.isGameOver)
    }

    @Test func movesThatDontReachTheWinningTileDontWin() throws {
        var session = try Self.session([[2, 2, 0], [0, 0, 0], [0, 0, 0]])
        session.move(.left)
        #expect(!session.hasWon)
        #expect(!session.shouldPresentWin)
    }

    @Test func tilesAboveTheWinningValueWin() throws {
        let session = GameSession(
            rules: Self.toEight, board: try Board(rows: [[16, 0, 0], [0, 0, 0], [0, 0, 0]]), seed: 1)
        #expect(session.hasWon)
    }

    @Test func acknowledgingKeepsPlaying() throws {
        var session = try Self.session(Self.oneMergeFromEight)
        session.move(.left)

        session.acknowledgeWin()

        #expect(!session.shouldPresentWin)
        #expect(session.hasWon)
        let acknowledged = session
        session.acknowledgeWin()
        #expect(session == acknowledged)
        #expect(session.move(.right) != nil)
        #expect(!session.shouldPresentWin)
    }

    @Test func acknowledgingWithoutAWinDoesNothing() {
        var session = GameSession(rules: .classic, seed: 1)
        let before = session
        session.acknowledgeWin()
        #expect(session == before)
    }

    @Test func winIsPresentedOncePerGame() throws {
        var session = try Self.session(Self.oneMergeFromEight)
        session.move(.left)
        session.acknowledgeWin()

        session.undo()
        #expect(session.board.highestTileValue == 4)
        #expect(session.hasWon, "undo doesn't take back the win")

        // Reaching the tile again, by a new move or by redo, isn't a new win.
        var swiped = session
        swiped.move(.left)
        #expect(swiped.board.highestTileValue == 8)
        #expect(!swiped.shouldPresentWin)
        session.redo()
        #expect(!session.shouldPresentWin)
        #expect(session.hasWon)
    }

    /// Until acknowledged, the win stays pending whatever the player does, so
    /// a quick swipe or undo can't skip it; it is still presented only once.
    @Test func winStaysPendingUntilAcknowledged() throws {
        var session = try Self.session(Self.oneMergeFromEight)
        session.move(.left)

        #expect(session.move(.right) != nil)
        #expect(session.shouldPresentWin)
        session.undo()
        session.undo()
        #expect(session.board.highestTileValue == 4)
        #expect(session.shouldPresentWin)
        session.redo()
        #expect(session.shouldPresentWin)

        session.acknowledgeWin()
        session.undo()
        session.redo()
        #expect(!session.shouldPresentWin)
        #expect(session.hasWon)
    }

    @Test func winningAndGameOverTogether() throws {
        let rules = GameRules(id: "to64", boardSize: 3, winningValue: 64)
        var session = GameSession(rules: rules, board: try Board(rows: Self.winsAndEnds), seed: 1)
        #expect(!session.hasWon)

        session.move(.left)

        #expect(session.shouldPresentWin)
        #expect(session.isGameOver)

        // No swipe is possible, and ignored swipes leave the win pending.
        let over = session
        for direction in Direction.allCases {
            #expect(session.move(direction) == nil)
        }
        #expect(session == over)

        session.acknowledgeWin()
        #expect(session.isGameOver)
        session.undo()
        #expect(!session.isGameOver)
        #expect(session.hasWon && !session.shouldPresentWin)
    }

    @Test func restartCanBeWonAgain() throws {
        var session = try Self.session(Self.oneMergeFromEight)
        session.move(.left)
        session.acknowledgeWin()

        session.restart()

        #expect(!session.hasWon)
        #expect(!session.shouldPresentWin)
    }

    /// With a winning value of 2 every board wins, including the first.
    @Test func startingBoardCanWin() {
        let rules = GameRules(id: "to2", boardSize: 3, winningValue: 2)
        var session = GameSession(rules: rules, seed: 1)
        #expect(session.shouldPresentWin)

        session.acknowledgeWin()
        session.restart()

        #expect(session.shouldPresentWin)
    }
}
