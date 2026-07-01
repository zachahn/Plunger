# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Plunger is a macOS menu-bar app that launches Ghostty terminal tabs from saved (path, command) pairs. It is a SwiftUI port of an earlier Go/menuet app; several source comments reference the original Go behavior they preserve. The app runs without the App Sandbox (no entitlements file), which is what lets `HTTPServer` bind a raw TCP listener and `Launcher` shell out to `osascript`.

## Build and test

Open `Plunger.xcodeproj` in Xcode, or from the command line:

```sh
# Run all tests (PlungerTests target; the pure-logic suite)
xcodebuild test -project Plunger.xcodeproj -scheme Plunger -destination 'platform=macOS' -only-testing:PlungerTests

# Run a single test
xcodebuild test -project Plunger.xcodeproj -scheme Plunger -destination 'platform=macOS' -only-testing:PlungerTests/RouterTests/rootWithAuthServesForm

# Build only
xcodebuild build -project Plunger.xcodeproj -scheme Plunger -destination 'platform=macOS'
```

There is one scheme, `Plunger`, covering the `Plunger`, `PlungerTests`, and `PlungerUITests` targets. Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest, except for the mostly-empty `PlungerUITests` target.

## Architecture

**State and persistence.** `ConfigStore` is the single `@Observable` source of truth, holding a `Config` (arrays of `paths` and `commands` strings) persisted as a property-list blob in `UserDefaults` under the `"config"` key — kept compatible with the original Go app's defaults format. `AuthToken` persists a separate random bearer token under its own `UserDefaults` key. Both `paths` and `commands` are deduplicated, order-preserving string lists (see `Array.appendUnique` in `Config.swift`); there is no `Entry`/tuple struct — a launch is just a `(path, command)` pair validated against both lists independently.

**Two UIs, one store.** `MenuContent` (menu-bar dropdown) and `EditPanelView` (a floating settings panel opened via "Settings…") both bind to the same `ConfigStore` and stay in sync through `@Observable`. The floating panel (`FloatingPanel.swift`) is plain AppKit — a non-activating `NSPanel` — because SwiftUI's `MenuBarExtra` has no equivalent that floats without stealing focus; `EditPanelController` owns its lazy construction and show/toggle lifecycle.

**Launching.** `Launcher.launch(path:command:)` is the one place that shells out: it builds an AppleScript string and runs `osascript` to open a new Ghostty window or tab. Both the menu bar and the HTTP server call this same function.

**HTTP server (`HTTPServer.swift`).** A dependency-free HTTP/1.1 server on `Network.framework`, listening on `0.0.0.0:8765` (every interface, reachable from the LAN) — this is why the bearer token matters and why the server is strictly launch-only. It never reaches a `ConfigStore` mutation method, only reads a `Router.StoreView` snapshot taken on the main actor before each request is routed off-actor. Routing (`Router.route`) is pure — request + read-only store view in, `RouteOutcome` out — so tests exercise it without spawning Ghostty or opening sockets; `.launch` outcomes carry the success response to send *after* `Launcher.launch` runs, so a browser form POST gets an HTML page and a JSON client gets JSON. Auth accepts either HTTP Basic (`plunger:<token>`) or a `Bearer plunger:<token>` header; the username is fixed to `"plunger"` in both.

**HTML templates.** `Plunger/Resources/*.html` and `style.css` are loaded from the app bundle and rendered via a minimal `{{key}}` placeholder substitution in `Template` (no loops or conditionals — every page has a handful of fixed slots). `HTMLPage` builds the actual pages (form, launched, unknown) on top of that.

**Command resolution (`CommandResolver.swift`).** A GUI app launched from Finder inherits a minimal `PATH` lacking Homebrew, so saving a command searches the process `PATH` first, then a fixed list of common bin directories (`/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`). `resolveCommand` rewrites just the first token (the program) and leaves arguments untouched. `programExists` is stricter and does no PATH search — it only accepts a command whose first token is already an absolute path to an executable file, which is what gates the "Save" button in `EditPanelView`'s command popover until the user presses "Resolve".
