# Floric

Floating, time-synced song lyrics for macOS. Reads the currently-playing
track directly from the local Spotify app — no Spotify Web API, no OAuth.

## Requirements

- macOS 14 (Sonoma) or newer
- Xcode 15+ (Swift 5.9+)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Build & Run

The Xcode project is generated from `project.yml` via XcodeGen. Regenerate
whenever you add files or change build settings.

```sh
xcodegen generate
open Floric.xcodeproj
```

Or build and run from the command line:

```sh
xcodegen generate
xcodebuild -project Floric.xcodeproj -scheme Floric -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/Floric-*/Build/Products/Debug/Floric.app
```

Floric runs as a menu-bar (status item) app — no Dock icon — driven by
`LSUIElement = true`. Look for the music-note glyph in your menu bar.

## Project Layout

```
Floric/              SwiftUI sources
  FloricApp.swift    @main entry point + MenuBarExtra scene
  Assets.xcassets    AppIcon catalog
project.yml          XcodeGen spec — source of truth for the Xcode project
```

`Floric.xcodeproj` is generated; do not hand-edit. Modify `project.yml`
and re-run `xcodegen generate`.

## Status

US-001 — project scaffold. Subsequent stories (Spotify integration,
lyrics fetching, floating window, etc.) land on top of this base.
