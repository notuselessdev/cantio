# TODO — Menubar panel

Status: **All milestones complete (M1–M3).** See per-milestone notes below.

Scope: `MenuBarExtra(.window)` panel UX.
Owner files: `Floric/MenuBarPanel.swift`, `Floric/Settings/SettingsScene.swift` (or wherever `SettingsLink` lives), `Floric/Spotify/SpotifyMonitor.swift`.

---

## M1 — Settings: focus existing window — ✅ DONE

Today: clicking Settings while window open spawns / re-opens vs raises.

- [x] Pre-check: enumerate `NSApp.windows`, find Settings window (identifier or title match), if visible → `makeKeyAndOrderFront` + `NSApp.activate(ignoringOtherApps: true)`.
- [x] Only call `SettingsLink` action when no existing window.
- [x] Activation policy still `.regular` while Settings on screen, `.accessory` on close (already done — verify).
- [x] Edge: Settings minimized to Dock → deminiaturize before front.

Acceptance: open Settings, close menubar panel, click Settings again from menubar → same window jumps to front, no duplicate.

Gotcha: SwiftUI `Settings` scene window has stable identifier; rely on identifier not localized title.

Implementation: `HoverableSettingsRow` + `findSettingsWindow` + `focusExistingSettingsWindow` in `MenuBarPanel.swift`.

---

## M2 — Real player controls — ✅ DONE

Today: menubar panel show now-playing display only.

Add real transport:
- [x] Play/Pause toggle button (icon swaps with `nowPlaying.state`).
- [x] Previous track button.
- [x] Next track button.
- [x] Interactive progress bar (seek on drag-end + tap).

Implementation:
- [x] Extend `SpotifyMonitor` (or new `SpotifyController`) with AppleScript actions: `playpause`, `previous track`, `next track`, `set player position to X`.
- [x] Background queue exec, `MainActor` UI update, optimistic state flip with rollback on error.
- [x] Progress bar: bind to `interpolatedPosition(now:)` already in monitor; on drag write back via `set player position`; throttle writes.
- [x] HIG: hit target ≥ 28pt, VoiceOver labels ("Play", "Pause", "Previous track", "Next track", "Seek to {time}"), keyboard shortcuts (Space = play/pause, ⌘← / ⌘→ = prev/next, ←/→ = seek ±5s) when menubar focused.
- [x] Reduce Motion: no progress animation interpolation flash on seek — snap.
- [x] Disable controls when `availability != .available`.

Acceptance: play/pause works, prev/next skip, drag scrubber to seek, position interpolates between polls, all VoiceOver-labeled, all keyboard-reachable.

Tests:
- [x] Mock `PlaybackSource` (already exists) — extend protocol w/ control methods.
- [x] Unit: tap play while paused → controller called `playpause()`.
- [ ] Snapshot: panel with controls in playing / paused / unavailable states. *(snapshot matrix updated on `MenuBarPanelSnapshotTests`; verify coverage)*

Implementation: `TransportControls`, `TransportButton`, `ScrubberRow` in `MenuBarPanel.swift`; protocol methods on `PlaybackSource` in `SpotifyMonitor.swift`.

---

## M3 — Remove theme picker from menubar — ✅ DONE

Today: theme (tone) selector lives in menubar panel.

- [x] Delete tone picker from `MenuBarPanel`. Keep in `PreferencesView` (Settings) only.
- [x] Reclaim vertical space for new player controls (M2).
- [x] Confirm pref still wired through Settings only — no broken bindings.

Acceptance: menubar panel has no tone picker. Settings → Appearance → tone picker still works. Switching tone in Settings reflects live.

---

## Post-M3 polish (2026-05-03 session)

- [x] Album art click → focus + deminiaturize Spotify (`NSWorkspace.openApplication`).
- [x] Artist click → opens in Spotify via `spotify:search:` URI (no longer browser).
- [x] "Hide lyrics window" row no longer renders permanently in active state — hover-only highlight.
- [x] Title + artist behave like links: hover underline + `NSCursor.pointingHand` (`LinkButton` wrapper).
- [x] `SpotifyMonitor` re-prompts TCC when state stays `.notDetermined` (post-logout/login + dismissed-prompt recovery).

---

## Test gates (all 3)

- [x] `swift-builder` after each.
- [ ] `hig-check` on diff (M2 UI is biggest risk — controls + scrubber).
- [ ] Snapshot record menubar panel in at least: playing/paused/unavailable × light/dark.
- [x] Manual: real Spotify with `spotify:track:<uri>` from `CLAUDE.local.md`.
