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

## Packaging & distribution

Floric ships as a universal (Apple Silicon + Intel) `.app` inside a
drag-to-Applications DMG. Release builds use a hardened runtime, are
signed with Developer ID, and are notarized + stapled.

```sh
export DEVELOPER_ID_APPLICATION="Developer ID Application: Acme LLC (TEAMID)"
export APPLE_TEAM_ID="ABCDE12345"
export APPLE_ID="you@example.com"
export APPLE_APP_PASSWORD="abcd-efgh-ijkl-mnop"   # app-specific password

scripts/build-release.sh
# → build/Floric.dmg
```

`SKIP_NOTARIZE=1 scripts/build-release.sh` skips notarization (useful for
local-only smoke tests of signing + DMG layout).

The script:

1. Regenerates the Xcode project via XcodeGen.
2. Archives a universal binary (`ARCHS = "arm64 x86_64"`).
3. Exports the `.app` with manual Developer ID signing + hardened runtime.
4. Verifies `lipo -archs` reports both slices and `codesign` reports the
   `runtime` flag.
5. Submits to Apple Notary Service (`xcrun notarytool ... --wait`) and
   staples the ticket.
6. Builds a `Floric.dmg` with a `/Applications` symlink for drag-to-install.

### Auto-update (Sparkle)

The Sparkle 2 framework is wired in via SwiftPM and exposed through the
"Check for Updates…" menu item. The update channel is **stubbed** — before
shipping a real release, replace the placeholders in `project.yml`:

- `INFOPLIST_KEY_SUFeedURL` — public URL of your `appcast.xml`.
- `INFOPLIST_KEY_SUPublicEDKey` — base64 EdDSA public key generated via
  Sparkle's `generate_keys` tool. Keep the matching private key out of
  version control and use it to sign new appcast entries.

See [Sparkle's documentation](https://sparkle-project.org/documentation/)
for the appcast format and signing workflow.

## Status

US-001 through US-010. Subsequent work iterates on packaging, the appcast
pipeline, and feature polish.
