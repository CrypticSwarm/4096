# CLAUDE.md

Native iOS game "4096" (2048 with a 4096 goal tile). See README.md for details.

## Environment

- Development host is Linux with a Swift 6 toolchain; there is no Xcode.
  Only the `GameCore` package can be built and tested locally.
- The iOS app is built and tested only by the `iOS` GitHub Actions workflow
  (macOS runner). Screenshots come from its `screenshots` artifact.

## Commands

```sh
make test     # run GameCore tests (Swift Testing)
make lint     # swift format lint --strict on all Swift files; CI fails on any finding
make format   # fix formatting in place
make check    # build + test + lint, as the Core CI job does
make help     # list all targets (ios-* targets need macOS)
```

Run `make format` then `make check` before every commit.

## Layout

- `GameCore/`: Swift package with all game logic (engine, session, persistence).
- `Game4096/`: SwiftUI app. `Game4096Tests/`: app unit tests. `Game4096UITests/`: XCUITests.
- `project.yml`: XcodeGen spec; never commit a generated `.xcodeproj`.
- `.github/workflows/`: `core.yml` (Linux), `ios.yml` (macOS simulator).
- `scripts/`: helpers called by the Makefile and CI.

## Conventions

- Game logic goes in `GameCore`, never in the app. It must not import UIKit,
  SwiftUI or other Apple-only frameworks, and every behavior gets a test there.
- Randomness in `GameCore` is injected (seedable) so tests are deterministic.
- Swift 6 language mode everywhere. Core tests use Swift Testing (`import Testing`);
  UI tests use XCTest/XCUITest.
- UI tests find elements by accessibility identifiers defined in
  `Game4096/AccessibilityID.swift`, which is compiled into both the app and the
  UI test target.
- New app files under `Game4096/` are picked up by XcodeGen automatically; new
  targets or settings go in `project.yml`.
- The Xcode version (`ios.yml`) and simulator (`Makefile`) must stay in sync with
  the macOS runner image.
- Commits: imperative subject line, short body explaining why. No attribution
  trailers (no `Co-Authored-By`, no "Generated with" lines).
