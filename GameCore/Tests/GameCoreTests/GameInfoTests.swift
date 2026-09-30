import GameCore
import Testing

struct GameInfoTests {
    @Test func titleIsGameName() {
        #expect(GameInfo.title == "4096")
    }
}
