# Floric Test Inventory

Prioritized list of unit-testable units, ranked by `value × ease`. No tests exist yet.

---

## Tier 1 — write first (trivial, < 30 min each)

Pure logic, no AppKit/network/Spotify deps. Zero refactor.

### `Lyrics/LRCParser.swift` :: `LRCParser.parse`
- Why: parser bugs corrupt every synced lyric line (off-by-one stamps, dropped chorus repeats, metadata leakage).
- DI: none.
- Difficulty: trivial. Cases: empty input, `[mm:ss]`, `[mm:ss.xx]`, `[mm:ss.xxx]`, multi-stamp line, `[ar:Foo]` metadata skipped, sort order preserved, malformed bracket.

### `Window/LyricsContentView.swift` :: `LyricLine.activeIndex(in:at:)`
- Why: binary search at boundaries — easy to get +/-1 wrong; controls which line is highlighted.
- DI: none.
- Difficulty: trivial. Cases: empty, single line, position before first (nil), position exactly on stamp, position past last, position between two.

### `Window/LyricsContentView.swift` :: `LyricPosition.compute(lines:position:)`
- Why: drives prev/current/next rendered words. Off-by-one breaks fullscreen + pillStack.
- DI: none.
- Difficulty: trivial. Cases: empty lines, position before first (current nil, next=lines[0]), middle, last (next nil), single-line, empty-text → "♪" fallback, words split.

### `Lyrics/LyricsCache.swift` :: `LyricsCache` (round-trip + state mapping)
- Why: persistence schema regressions silently re-fetch; key sanitization must not collide.
- DI: `init(fileManager:)` — strategy doc says use temp directory, not mock. Easy.
- Difficulty: trivial. Cases: `save`/`load` round-trip synced + plain + miss; `entry(from:)` for every `LyricsState` case (idle/loading/error → nil); `state(from:)` covers empty synced→notFound; `sanitize` strips `/`, `:`, unicode → `_`; `summary()` on empty dir.

### `Settings/Preferences.swift` :: legacy migration in `init(defaults:)`
- Why: every legacy preset → current `WindowStyle`/`BackgroundStyle` mapping; user upgrade path.
- DI: pass `UserDefaults(suiteName:)` per test (per strategy §6).
- Difficulty: trivial. Cases: `windowPreset = "minimal"|"fullscreen"|"glass"|"solid"|nil` → expected `windowStyle` + `backgroundStyle`; explicit `windowStyle` wins over legacy; absent `fontSize` → `.medium`; absent `hideWhenPaused`/`alwaysOnTop`/`windowVisible` → `true`; missing hotkey → `.defaultToggle`; stored hotkey round-trip.

### `Hotkey/HotKey.swift` :: `HotKey.carbonModifiers(from:)` + `displayString`
- Why: encoder must round-trip NSEvent → Carbon flags both directions; wrong flags = silent hotkey failure.
- DI: none (pure on flag bits).
- Difficulty: trivial. Cases: each single modifier maps; combined ⌥⌘ maps; `displayString` order is `⌃⌥⇧⌘<key>`; F-keys + arrows hit the lookup table; `defaultToggle` → "⌥⌘L".

### `Window/LyricsContentView.swift` :: `FlowLayout`
- Why: word-wrap geometry across widths; bug = clipped lyrics.
- DI: none — Layout protocol is pure given subviews. Use `Layout.Subviews` test fixtures or wrap in NSHostingView and read frames.
- Difficulty: trivial-to-light. Cases: single word fits; wrap when row exceeds maxW; centering math; spacing between words.

### `Design/Tokens.swift` :: `FL.palette(tone:hue:)` + `FL.oklch`
- Why: deterministic color outputs guard against accidental design-token drift.
- DI: none. (`FL.resolveTone(nil)` is the only AppKit-touching path — skip; test the explicit-tone overload.)
- Difficulty: trivial. Snapshot a handful of (tone, hue) → expected sRGB tuples; assert gamma clamps to 0..1.

---

## Tier 2 — write next (needs mocks or small refactor)

### `Spotify/SpotifyMonitor.swift` :: `runScript(_:)` parser
- Why: AppleScript line-buffer parsing — duration ms→s heuristic, 7-vs-8 fields (artwork), `ERR_*` sentinels, error code -1743 → permissionDenied.
- DI: needs refactor — extract `parseScriptOutput(_ raw: String) -> PollResult` from `runScript` so tests don't need NSAppleScript. Also extract `errorPollResult(code: Int)` for the -1743 mapping.
- Difficulty: needs-refactor (10-min extract, then trivial tests). Cases: 7 fields no artwork; 8 fields with artwork; empty artwork → nil; ms duration → /1000; sub-1000 already in seconds; `ERR_NOT_RUNNING`; `ERR_NO_TRACK`; <7 parts → notRunning; whitespace trimming.

### `Spotify/SpotifyMonitor.swift` :: `interpolatedPosition(now:)`
- Why: drives lyric scroll precision. Bug = visible drift.
- DI: depends on `positionAnchor` — already settable internally but `Date` is injected via param. Best fix: extract a free function `interpolate(anchor: PositionAnchor, now: Date) -> Double` so monitor isn't constructed.
- Difficulty: needs-refactor (small). Cases: nil anchor → nil; paused → returns anchor.position regardless of `now`; playing → position + delta; negative delta clamped to 0.

### `Spotify/NowPlaying.swift` :: `PlayerState.init(appleScriptValue:)`
- Why: case-insensitive mapping, unknown fallthrough.
- DI: none.
- Difficulty: trivial — promote to Tier 1 if you have time. Cases: "Playing"/"PLAYING"/"playing" → .playing; "Paused"; "Stopped"; "" / "weird" → .unknown.

### `Lyrics/LyricsStore.swift` :: `handle(_:)` state machine
- Why: cache-hit short-circuit, late-fetch guard against track switch, nil-track resets, dup-track ignores.
- DI: needs `LyricsService` + `SpotifyMonitor` to be protocols (`LyricsProvider`, `PlaybackSource` per strategy §4). Currently both concrete. `bind(to:)` calls `monitor.events` — needs `PlaybackSource.events`.
- Difficulty: needs-refactor. Cases (after seam): cache hit → no fetch; cache miss → fetch then save; same trackId twice → no second fetch; track changes mid-fetch → late result discarded; nil → `.idle`.

### `Lyrics/LyricsService.swift` :: `fetch(track:)`
- Why: HTTP status routing (404→notFound, 5xx→error, 2xx empty→notFound, 2xx synced→parse, 2xx plain→plain).
- DI: `URLSession` is already a stored property — inject a session with a custom `URLProtocol` stub. No source changes needed.
- Difficulty: needs-mock. Cases: 200 synced; 200 plain only; 200 both empty; 200 synced parse fails → falls back to plain; 404 → notFound; 500 → error; transport throw → error; query items include duration rounded.

### `Settings/Preferences.swift` :: `didSet` cascades
- Why: `windowStyle`/`linesVisible` recompute `displayMode` — bidirectional state coupling.
- DI: fresh `UserDefaults(suiteName:)`.
- Difficulty: trivial-but-needs-MainActor. Cases: set `linesVisible = 1` → `displayMode == .singleLine`; set `linesVisible = 3` → `.multiLine`; toggle hotkey persists keyCode + modifiers integers.

---

## Tier 3 — defer (snapshot / UI / low value)

- `Window/LyricsContentView.swift` body — snapshot territory (matrix in strategy §2).
- `Window/FloatingLyricsController.swift` / `FloatingLyricsWindow.swift` — AppKit window plumbing → UI test.
- `Hotkey/HotKeyManager.swift` — Carbon `RegisterEventHotKey` side effects, no return value to assert. UI test only.
- `Hotkey/HotKeyRecorder.swift` — NSEvent monitor, NSView. UI / manual.
- `Settings/PreferencesView.swift` — snapshot.
- `Spotify/SpotifyPermission.swift` — wraps TCC; can't drive in unit tests.
- `Spotify/SpotifyMonitor.poll()` / `loop()` — orchestrates AppleScript + global queue + permission prompt; defer until protocol seam exists, then test via `MockPlaybackSource` at the call site (LyricsStore).
- `Design/FloricIcon.swift` — Canvas drawing → snapshot.
- `Lyrics/LyricsCache.summary()` ByteCountFormatter output — locale-dependent; low value.
- `Updates/*`, `MenuBarPanel.swift`, `FloricApp.swift` — wiring; UI smoke test covers.
- `HotKey.keyName` non-table path (UCKeyTranslate) — depends on system keyboard layout, brittle.

---

## Recommended first wave

For `test-author` to write next, in order:

1. `LRCParserTests` — parse all timestamp shapes + metadata skip + multi-stamp.
2. `LyricLineActiveIndexTests` — boundary + empty + single + binary-search edges.
3. `LyricPositionTests` — prev/current/next across positions including before-first.
4. `LyricsCacheTests` — round-trip + `entry(from:)`/`state(from:)` for every state + sanitize.
5. `PreferencesMigrationTests` — every `windowPreset` legacy mapping + default fallbacks + hotkey round-trip.
6. `HotKeyTests` — `carbonModifiers(from:)` both directions + `displayString` ordering + `defaultToggle`.
7. `FlowLayoutTests` — single row, wrap, centering at multiple widths.

These seven cover the strategy doc's bootstrap step 5 plus parser/hotkey high-value targets, with no source refactor required.
