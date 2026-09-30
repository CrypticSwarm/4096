import GameCore
import Testing

@Suite struct GameInfoTests {
    @Test func titleIsGameName() {
        #expect(GameInfo.title == "4096")
    }
}
