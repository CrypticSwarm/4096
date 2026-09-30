# 4096

A native iOS take on 2048 where the goal tile is 4096. Built with SwiftUI; the
game rules live in a platform-independent Swift package so they can be
developed and tested without a Mac.

Status: the game is playable: the classic 4×4 game with 2048's look and
animations, the score and best score, undo and redo of the last three moves,
a one-time win at 4096 with the option to keep playing, a game over message,
a confirmed New Game, and the game in progress saved across launches. Game
variants (such as 5×5) exist in `GameCore` but can't be chosen in the app yet.

## Repository layout

| Path | What |
| --- | --- |
| `GameCore/` | Swift package with all game logic. No UIKit/SwiftUI; builds and tests on Linux. |
| `Game4096/` | SwiftUI app target (sources and asset catalog). |
| `Shared/` | Files compiled into both the app and the UI tests (e.g. accessibility identifiers). |
| `Game4096Tests/` | App unit tests (Swift Testing), hosted in the app. |
| `Game4096UITests/` | XCUITests that drive the app and attach screenshots. |
| `project.yml` | XcodeGen spec for the Xcode project. The `.xcodeproj` is generated, not committed. |
| `Makefile` | Entry points for local work and CI (`make help`). |
| `scripts/` | Helpers used by `make` and CI. |
| `.github/workflows/` | CI: `core.yml` (Linux) and `ios.yml` (macOS). |

## Game engine

`GameCore` implements the rules of the original 2048 as pure value types:

- `Board`: a square grid of tile values (row 0 is the top row). `sliding(_:)`
  slides and merges in a `Direction` and returns a `SlideResult` describing
  where every tile went, for animation. `hasAvailableMoves` is `false` when the
  game is over.
- `GameRules`: a variant's parameters (board size, winning tile, starting
  tiles, spawn distribution) with a stable `id`; `GameRules.classic` is 4×4
  played to 4096. `move(_:on:using:)` slides and spawns a random tile, returning
  a `Move`, or `nil` when the swipe changes nothing.
- `Move`: a slide plus its `Spawn`. The direction and spawn replay it exactly.
- `SplitMix64`: a seedable random number generator, so games are reproducible.
- `TileLayout`: the board's tiles with stable ids for animation. `apply(_:)`
  follows a `Move` and returns a `TileTransition` (which tiles slid where,
  which merged, which spawned); `reset(to:)` renumbers all tiles after any
  other change, such as a new game.

## Launch arguments

For UI tests and development, the app reads these launch arguments (parsed by
`LaunchConfiguration` in `GameCore`; others are ignored):

| Argument | Effect |
| --- | --- |
| `-seed <UInt64>` | Seeds the random number generator, so spawns (and the starting board of a new game) are reproducible. A saved game keeps its own generator. |
| `-board <notation>` | Starts from this board instead of the saved game (which the first change then replaces). Rows top to bottom separated by `;`, values separated by `,`, 0 for empty, no spaces, at least one tile: `-board "2,2,0,0;0,0,0,0;0,0,0,0;0,0,0,4"`. The board's size (2 to 16) picks the game's board size. A board with a 4096 tile starts as just won. |
| `-score <Int>` | The score of the `-board` game (default 0). Only with `-board`. |
| `-highScore <Int>` | Raises the best score to at least this value (and the stored one, on the first change). |
| `-storage <memory or folder>` | `memory` keeps games and scores in memory only, so nothing is read or kept; any other value is the name of the folder in Application Support to save in instead of `Saves`. |

Without `-board`, the app continues the game saved in the chosen storage, or
starts a new one. The UI tests launch with `-storage memory`, except the
persistence test, which uses a folder of its own and relaunches the app.

The board element's accessibility value is the current board in the same
notation, and the score boxes' values are the scores, so UI tests can check
the exact state.

## Game session

`GameSession` is a game in progress as a value type: rules, board, score, high
score, undo and redo history, win state and its generator. The app's view
model holds one and calls its methods:

- `move(_:)` plays a swipe and returns the `Move` to animate, or `nil` for a
  swipe that changes nothing (which is ignored entirely).
- `undo()` takes back the last move; `redo()` replays an undone move with the
  same spawned tile and returns it to animate. The session remembers three
  moves, counting those that can be undone and those that can be redone
  together. A new swipe after undo draws a new tile and drops the moves that
  could have been redone.
- `shouldPresentWin` turns `true` once per game, when a winning tile is first
  reached, and stays `true` until `acknowledgeWin()`. Undo doesn't take the
  win back. `isGameOver` is `true` when no swipe changes the board; undo still
  works then.
- `restart()` starts a new game, clearing undo and redo.
- `highScore` is the best score reached in the variant, raised by the session
  itself and never lowered, not even by undo or restart.

`GameStore` saves one game per variant and the high scores in a `GameStorage`:
`FileGameStorage` (JSON files in a directory the app chooses, written
atomically) or `InMemoryGameStorage` (tests, previews, UI tests). The formats
are versioned; a saved game that can't be restored loads as a new game that
keeps the high score. Storage errors are thrown rather than treated as a missing
game, so the app can avoid saving over a game it couldn't read.

## App

The SwiftUI app in `Game4096/` is a thin layer over `GameCore`:

- `GameModel` (`@MainActor`, `@Observable`) owns the `GameSession` and the
  `TileLayout` that draws its board. Every action (move, undo, redo, keep
  playing, new game) goes through one private `update` method that changes the
  session, then updates the tiles (a move or redo animates through
  `layout.apply`; undo and a new game replace the tiles with `layout.reset`),
  records the change (`lastChange`) and saves the session with `GameStore`.
  So the tiles, the session and the saved game can't disagree. It also
  decides which message shows over the board (`overlay`) and whether Undo and
  Redo are available.
- Saving: games and best scores are saved in `Application Support/Saves` with
  `FileGameStorage`, after every change; moving to the background retries a
  save that failed. If the saved game can't be read, the app plays a new game
  (keeping the best score if that can be read) without saving, so it doesn't
  overwrite what it couldn't read, says so under the board, and tries to load
  it again when the app becomes active, as long as the player hasn't played
  yet. A failed save is reported the same way and retried on the next change.
- Views only read the model and call its actions: `ContentView` lays out the
  title and `ScoreBox`es, the goal and New Game above the board, the board
  with its `GameMessageView` (win or game over), and Undo and Redo below the
  board. `BoardView` animates the tiles (`TileAnimation`); `Theme` holds the
  look, including how text fits at every Dynamic Type size (one line that
  shrinks for titles, numbers and buttons; wrapping for sentences; a single
  cap for the game's chrome). With VoiceOver, each change is announced in one sentence group
  (`MoveAnnouncement`): the move, the score and any message.
- While the win message shows, moves, undo and redo wait for Keep playing or
  New Game, as in the original. The game over message covers only the board,
  so Undo stays available. New Game always asks for confirmation, since it
  can't be undone.

## Local development

### Core package (Linux or macOS)

Needs a Swift 6 toolchain, which includes `swift format`. Use the same Swift
version as CI (see below) so `make lint` agrees with CI.

```sh
make build    # swift build the GameCore package
make test     # swift test the GameCore package
make lint     # swift format lint --strict over every Swift file in the repo
make format   # reformat every Swift file in place
make check    # build + test + lint, the same steps as the Core CI job
```

Formatting rules are in `.swift-format`.

### iOS app (macOS only)

Needs Xcode 26 (with an iPhone 17 simulator), [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`) and optionally `xcbeautify`.

```sh
make ios-project      # generate Game4096.xcodeproj from project.yml (to open it in Xcode)
make ios-test         # regenerate, then run app unit, UI and GameCore tests on the simulator
make ios-attachments  # export screenshots from the last run to build/attachments
make ios-summary      # print a Markdown summary of the last run
```

`ios-test` writes `build/TestResults.xcresult` and `build/xcodebuild.log`.
Pick a different simulator with
`make ios-test IOS_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'`.

## Continuous integration

| Workflow | Job | Runs on | Triggers |
| --- | --- | --- | --- |
| `Core` (`core.yml`) | Build, test and lint (Linux) | Swift container on Ubuntu | every branch push, manual |
| `iOS` (`ios.yml`) | Build and test (iOS Simulator) | macOS runner | every branch push, manual; skipped when only Markdown, `.editorconfig` or `.swift-format` change |
| `iOS` (`ios.yml`) | Publish screenshots | Ubuntu | after the iOS job, unless the run was cancelled |

Neither workflow runs for `ci-screenshots`. Both jobs that build call the same
`make` targets as local development. Failures show up as annotations on the
commit and in each run's job summary. The iOS job uploads two artifacts:
`screenshots` (PNG attachments from the UI tests) and `test-results` (the
`.xcresult` bundle and raw `xcodebuild` log).

The publish job commits the screenshots to the orphan branch `ci-screenshots`
under `<branch>/<short-sha>/` (`scripts/ci/publish-screenshots.sh`), so they
can be viewed without downloading artifacts, e.g.
`https://raw.githubusercontent.com/CrypticSwarm/4096/ci-screenshots/<branch>/<short-sha>/<name>.png`,
where `<name>` is the attachment's name in the UI test; a notice annotation
links the folder. It is the only job with write access, and publishing is
best effort: it warns instead of failing. The branch only accumulates
screenshots; delete it whenever it gets large, and the next run recreates it.
To keep it out of a clone, run
`git config --add remote.origin.fetch '^refs/heads/ci-screenshots'`.

Since iOS runs on pushes, not pull requests, a push that only changes
documentation has no iOS run, so a branch's head commit may lack one.

Where versions are pinned:

- Swift: the `container` image in `core.yml`.
- Xcode and XcodeGen: `XCODE_VERSION` and `XCODEGEN_VERSION` (plus checksum) in `ios.yml`;
  `options.xcodeVersion` in `project.yml` tracks the Xcode major version.
- macOS runner image: `runs-on` in `ios.yml`.
- Simulator: `IOS_DESTINATION` in the `Makefile`.
- iOS deployment target: `project.yml` and `GameCore/Package.swift`.

The runner image, Xcode version and simulator must agree; check the
[runner image readme](https://github.com/actions/runner-images/tree/main/images/macos)
when changing any of them.

## Developing without a Mac

The app can only be built and run on macOS, so this project relies on CI:

- Game logic belongs in `GameCore` and is covered by tests that run on Linux
  with `make test` (CI also runs them on the iOS simulator).
- The app, its unit tests and UI tests run only in the iOS workflow. To see the
  app, open the screenshots published to the `ci-screenshots` branch (or
  download the `screenshots` artifact) from a workflow run.
- There is no code signing yet; everything targets the simulator. Getting
  builds onto a device (TestFlight) needs an Apple Developer account and comes
  later.
