import GameCore
import Testing

@testable import Game4096

@MainActor
struct GameModelTests {
    @Test func startsFromTheConfiguredBoard() throws {
        let board = try Board(notation: "2,2,0,0;0,0,0,0;0,0,0,0;0,0,0,4")
        let model = GameModel(configuration: LaunchConfiguration(seed: 1, board: board))
        #expect(model.layout.board == board)
        #expect(model.layout.lastTransition == nil)
    }

    @Test func sameSeedSameStartingBoard() {
        let first = GameModel(configuration: LaunchConfiguration(seed: 5))
        let second = GameModel(configuration: LaunchConfiguration(seed: 5))
        #expect(first.layout.board == second.layout.board)
        #expect(first.layout.board.tileCount == GameRules.classic.startingTileCount)
    }

    @Test func performPlaysTheEnginesMove() throws {
        let board = try Board(notation: "2,2,0,0;0,0,0,0;0,0,0,0;0,0,0,4")
        let model = GameModel(configuration: LaunchConfiguration(seed: 3, board: board))

        #expect(model.perform(.left))

        var generator = SplitMix64(seed: 3)
        let expected = try #require(GameRules.classic.move(.left, on: board, using: &generator))
        #expect(model.layout.board == expected.board)
        #expect(model.layout.lastTransition?.direction == .left)
    }

    @Test func swipeThatChangesNothingIsIgnored() throws {
        let board = try Board(notation: "2,0,0,0;4,0,0,0;0,0,0,0;0,0,0,0")
        let model = GameModel(configuration: LaunchConfiguration(seed: 3, board: board))
        let before = model.layout

        #expect(!model.perform(.left))
        #expect(!model.perform(.up))

        #expect(model.layout == before)
    }

    @Test func newGameResetsWithoutATransition() throws {
        let board = try Board(notation: "2,2,0,0;0,0,0,0;0,0,0,0;0,0,0,4")
        let model = GameModel(configuration: LaunchConfiguration(seed: 3, board: board))
        model.perform(.left)

        model.newGame()

        #expect(model.layout.lastTransition == nil)
        #expect(model.layout.board.tileCount == GameRules.classic.startingTileCount)
    }

    @Test func fixtureOfAnotherSizeIsPlayed() throws {
        let board = try Board(notation: "2,2,0,0,0;0,0,0,0,0;0,0,0,0,0;0,0,0,0,0;0,0,0,0,0")
        let model = GameModel(configuration: LaunchConfiguration(seed: 3, board: board))
        model.perform(.right)
        #expect(model.layout.board.size == 5)
        #expect(model.layout.board[Position(row: 0, column: 4)] == 4)
    }
}
