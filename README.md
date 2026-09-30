# 4096

A native iOS take on 2048 where the goal tile is 4096. Built with SwiftUI; the
game rules live in a platform-independent Swift package so they can be
developed and tested without a Mac.

Status: the game engine is done. The app still shows a placeholder title
screen; the session (undo/redo, persistence, high scores) and game UI are still
to come.

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
