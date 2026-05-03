# Testing Strategy — Floric

Goal: every change is verified, not guessed. No regressions slip through. Tests
exist at the right altitude for the cost of writing + maintaining them.

---

## 1. Test pyramid

```
                ┌──────────────┐
                │   UI tests   │  ← few; cmd flows + critical paths
                ├──────────────┤
                │ Snapshot/UI  │  ← per-view × prefs matrix
                ├──────────────┤
                │   Unit       │  ← pure logic, parsers, state machines
                └──────────────┘
```

| Layer       | Tool             | Cost   | Coverage target | Run on             |
| ----------- | ---------------- | ------ | --------------- | ------------------ |
| Unit        | XCTest           | low    | ~85% of pure-logic types | every change |
| Snapshot    | swift-snapshot-testing | medium | full UI matrix per view | every UI change |
| UI / E2E    | XCUITest         | high   | smoke flows only       | pre-release        |

---

## 2. What goes where

### Unit tests (XCTest)

Pure-logic types — no AppKit, no SwiftUI, no Spotify dependency:

- **`Preferences`** — defaults, migrations from legacy keys, didSet side effects, hot-key encode/decode.
- **`LyricLine.activeIndex`** — binary search at boundaries, empty input, single item, position before first.
- **`LyricPosition.compute`** — prev/current/next correctness across track positions.
- **`LyricsCache`** — write/read/expire, key derivation, atomic replacement.
- **`SpotifyMonitor` parsers** — AppleScript output → `NowPlaying` mapping; permission-denied error paths.
- **`HotKey` encoder** — Carbon modifier flag conversion both directions.
- **`FL.Palette` / `FL.oklch`** — deterministic outputs per (tone, hue) input.
- **`FlowLayout`** — sizeThatFits + placeSubviews under various widths.

### Snapshot tests (swift-snapshot-testing)

Render `LyricsContentView` to image, compare against golden. Matrix per view:

- `windowStyle` × `backgroundStyle` × `tone` × state (playing/paused/no-music/no-permission).
- Two `accentHue` samples (220, 20).
- Two `linesVisible` samples (1, 3).
- One `fontSize` sweep at small + large.

Gives ~60 snapshots covering the visual regression matrix in `docs/apple-hig-checklist.md` §13.

Also snapshot:
- `MenuBarPanel` — both tones, glass + solid backdrop.
- `SettingsView` — both tones.
- `PillCapsule` — active + inactive, glass + solid, both tones.
- `WordView` — fill 0/0.5/1, isCurrent on/off.

### UI tests (XCUITest)

Cover flows that span windows and depend on AppKit wiring:

- App launches → menu-bar item visible.
- Open menu → toggle "Hide lyrics window" → floating panel hides → toggle back → reappears.
- Open Settings via menu → window appears in cmd-tab → close → app returns to accessory.
- Change `windowStyle` in Settings → floating panel re-renders with new chrome.
- Hot-key triggers visibility toggle.
- Cmd+Q quits cleanly.

Mock Spotify availability via injection (see §4) — UI tests never depend on real Spotify state.

---

## 3. Coverage targets

- **Pure logic:** 85%+ line coverage (must include error paths).
- **Views:** 100% of variant matrix has snapshot coverage.
- **State machines** (`SpotifyMonitor.availability`, `LyricsStore.state`): all transitions tested.
- **Migrations** (`Preferences` legacy key reads): test every legacy → current mapping.

CI fails if:
- Coverage drops > 2%.
- Any snapshot diff present (must be approved by re-recording).
- Any UI test fails.

---

## 4. Dependency injection for testability

Concrete types currently used directly. Refactor toward protocols at seams:

```swift
protocol PlaybackSource {
    var availability: SpotifyAvailability { get }
    var nowPlaying: NowPlaying? { get }
    func interpolatedPosition(now: Date) -> Double?
    func start()
}

protocol LyricsProvider {
    func fetch(for track: NowPlaying) async throws -> LyricsResult
}
```

Real implementations: `SpotifyMonitor: PlaybackSource`, `LRCLibProvider: LyricsProvider`.
Test implementations: `MockPlaybackSource`, `StubLyricsProvider`.

`FloatingLyricsController`, `LyricsStore`, `LyricsContentView` accept the
protocol, not the concrete type. Snapshot tests inject deterministic state.

This is the `swift-protocol-di-testing` pattern — non-negotiable for snapshot
tests because we can't drive real Spotify in CI.

---

## 5. Snapshot recording workflow

- Snapshots stored under `FloricTests/__Snapshots__/<TestCaseName>/`.
- Re-record only when intentional visual change: `record: true` flag → run → review diff → set back to `false`.
- Commit snapshot images with the change. PR diff shows pixel changes.
- Reviewer rejects PR if snapshot diff doesn't match described change.

---

## 6. Mocking policy

- **Mock at the protocol seam**, not in the middle of a type.
- **Never mock UserDefaults** — use a fresh `UserDefaults(suiteName:)` per test.
- **Never mock the file system** in `LyricsCache` tests — use a temp directory.
- **Never mock Date/Time** with global swizzles — pass `Date` explicitly.
- **Always mock**: AppleScript execution, network calls (LRCLIB), Carbon hot-key registration.

---

## 7. Test naming + organization

```
FloricTests/
├── Lyrics/
│   ├── LyricLineTests.swift
│   ├── LyricPositionTests.swift
│   └── LyricsCacheTests.swift
├── Settings/
│   ├── PreferencesTests.swift
│   └── PreferencesMigrationTests.swift
├── Spotify/
│   ├── SpotifyMonitorParserTests.swift
│   └── NowPlayingTests.swift
├── Window/
│   ├── HotKeyTests.swift
│   └── FlowLayoutTests.swift
├── Snapshots/
│   ├── LyricsContentViewSnapshotTests.swift
│   ├── MenuBarPanelSnapshotTests.swift
│   └── PreferencesViewSnapshotTests.swift
├── Mocks/
│   ├── MockPlaybackSource.swift
│   └── StubLyricsProvider.swift
└── UI/
    └── FloricUITests.swift  (XCUITest target)
```

Test method naming: `test_<unit>_<condition>_<expected>()`
- `test_activeIndex_emptyLines_returnsNil()`
- `test_compute_positionAtBoundary_returnsNextLine()`
- `test_preferences_legacyGlassPreset_migratesToMinimalGlass()`

---

## 8. Regression test audit (recurring task)

Every quarter, run `regression-auditor` agent (see `.claude/agents/`):

1. Diff all view snapshots against last release tag.
2. Identify drift not covered by intentional commits.
3. Re-test bug fixes from past 90 days — confirm each is still fixed.
4. Identify untested files added since last audit; spawn `test-author` agent to fill gaps.
5. Output gap report → `docs/test-gaps-YYYY-QN.md`.

---

## 9. Workflow per change

```
            ┌───────────────────┐
            │  Make code change │
            └─────────┬─────────┘
                      ▼
       ┌─────────────────────────────┐
       │ swift-builder runs build    │  ← spawned by you or hook
       │ (errors block proceed)      │
       └─────────┬───────────────────┘
                 ▼
       ┌─────────────────────────────┐
       │ test-author writes/updates  │  ← if logic change or new code path
       │ unit tests for change       │
       └─────────┬───────────────────┘
                 ▼
       ┌─────────────────────────────┐
       │ Run xcodebuild test         │
       │ (unit + snapshot)           │
       └─────────┬───────────────────┘
                 ▼
        ┌────────┴──────────┐
        │ if UI change:     │
        │ hig-reviewer +    │  ← parallel team
        │ a11y-auditor      │
        │ review the diff   │
        └────────┬──────────┘
                 ▼
       ┌─────────────────────────────┐
       │ Commit only when all green  │
       └─────────────────────────────┘
```

Hooks (see `.claude/settings.json`):

- `PostToolUse` after `Edit`/`Write` of `*.swift` → spawn `swift-builder` to compile + report errors.
- `Stop` → if changed `*.swift` files exist uncommitted → remind to run tests.
- `PreToolUse` on `git commit` → fail if `xcodebuild test` not green within last 5 minutes.

---

## 10. Bootstrap order (next steps)

1. Add `FloricTests` + `FloricUITests` targets to Xcode project.
2. Add `swift-snapshot-testing` via SPM.
3. Refactor `SpotifyMonitor` + `LRCLibProvider` behind protocols.
4. Write `MockPlaybackSource` + `StubLyricsProvider`.
5. Write first 5 unit tests (LyricLine + LyricPosition + LyricsCache + Preferences migration + FlowLayout).
6. Write first 3 snapshot tests (PillCapsule, MenuBarPanel, LyricsContentView pill+glass+dark).
7. Write 1 UI smoke test (launch → menu opens).
8. Wire CI script: `xcodebuild -scheme Floric test`.
9. Add hooks for build-on-edit + commit-gate.

This order = each step verifies the previous before adding more surface.
