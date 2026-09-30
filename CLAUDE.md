# CLAUDE.md

Native iOS game "4096" (2048 with a 4096 goal tile). See README.md for details.

## Environment

- Development host is Linux with a Swift 6 toolchain; there is no Xcode. If
  `swift` is not on PATH, try `export PATH=$HOME/.local/swift/usr/bin:$PATH`.
- Only `GameCore` can be built and tested locally. App and UI test code is
  only compiled by the `iOS` GitHub Actions workflow (macOS runner); check its
  annotations and job summary. It runs on every branch push. Its UI test
  screenshots are published to the `ci-screenshots` branch at
  `<branch>/<short-sha>/<name>.png`, where `<name>` is the attachment's name
  (readable via raw.githubusercontent.com), and uploaded as the `screenshots`
  artifact.

## Commands

```sh
make format   # fix formatting in place
make check    # build + test + lint GameCore; lint is strict and covers all Swift files
make help     # list all targets (ios-* targets need macOS)
```

Run `make format` then `make check` before every commit.

## Layout

- `GameCore/`: Swift package for all game logic. It has the engine (board,
  slides, spawns, rules; see README.md "Game engine"); session and persistence
  go here as they are added.
- `Game4096/`: SwiftUI app. `Game4096Tests/`: app unit tests. `Game4096UITests/`: XCUITests.
- `Shared/`: compiled into both the app and the UI tests (accessibility identifiers).
  Launch arguments are parsed and built by `LaunchConfiguration` in `GameCore`,
  which the UI tests also link (see README.md "Launch arguments").
- `project.yml`: XcodeGen spec; never commit a generated `.xcodeproj`.
- `.github/workflows/`: `core.yml` (Linux), `ios.yml` (macOS simulator).
- `scripts/`: helpers called by the Makefile and CI.

## Conventions

- Game logic goes in `GameCore`, never in the app. It must not import UIKit,
  SwiftUI or other Apple-only frameworks, and every behavior gets a test there.
- The app uses `GameCore` as a separate module, so anything it needs must be `public`.
- Randomness and storage must be injected into `GameCore` (a seedable RNG; a
  storage abstraction with an in-memory implementation) so tests and UI tests
  are deterministic; the app chooses where data is saved.
- Swift 6 language mode everywhere. Core and app unit tests use Swift Testing
  (`import Testing`); UI tests use XCTest/XCUITest.
- UI tests find elements by accessibility identifiers from `Shared/AccessibilityID.swift`.
- New files under existing target folders are picked up by XcodeGen automatically;
  new targets or settings go in `project.yml`.
- Pinned versions (Swift, Xcode, XcodeGen, runner image, simulator) are listed in
  README.md under "Continuous integration"; change coupled ones together.
- Commits: imperative subject line, short body explaining why. No attribution
  trailers (no `Co-Authored-By`, no "Generated with" lines).
