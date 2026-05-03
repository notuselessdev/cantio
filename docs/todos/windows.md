# TODO — Window styles

Status: **All milestones complete (W1–W4).** Bundled as one Wave 1B "windows pass."

Scope: floating lyrics window behavior across `pill` / `minimal` / `fullscreen` styles.
Owner files: `Floric/Floating/FloatingLyricsController.swift`, `Floric/Floating/FloatingLyricsWindow.swift`, `Floric/Settings/Preferences.swift`.

---

## W1 — Minimal: no click-through — ✅ DONE (subsumed by W4)

Minimal is real chrome window, not floating overlay. Click-through inappropriate.

- Force `clickThrough = false` whenever `windowStyle == .minimal` (ignore stored pref).
- `ignoresMouseEvents` always `false` for minimal.
- Hide / disable click-through toggle in Settings when minimal selected (or grey + helper text).
- Keep stored value untouched so switching back to pill restores prior choice.

Acceptance: minimal window receive clicks, drag, hover. Toggling `clickThrough` pref no effect while minimal active. Switch to pill → previous toggle state honored.

---

## W2 — Fullscreen actually fullscreen — ✅ DONE

Window level: `.statusBar` (over native fullscreen Spaces). Screen pick: `window.screen ?? .main ?? screens.first`. Frame: `screen.frame` (covers menubar+Dock).

Today: bigger window. Want: real fullscreen overlay covering whole active screen, all spaces.

- Pick `NSScreen` strategy: window currently on, OR follow mouse, OR primary. Decide + document. Suggest: screen window currently lives on, fall back to `NSScreen.main`.
- Frame = `screen.frame` (not `visibleFrame` — cover menubar + Dock for true fullscreen feel). Confirm w/ HIG: floating utility may want `visibleFrame` to avoid menubar overlap. Decide explicitly.
- `collectionBehavior` keep `.canJoinAllSpaces` + `.fullScreenAuxiliary` so coexists with native fullscreen apps.
- Disable user resize / move while in fullscreen (`isMovable = false`, no resize cursor).
- Track screen change: observe `NSApplication.didChangeScreenParametersNotification` + reflow.
- Restore prior pill/minimal frame when leaving fullscreen (don't blow away autosave).

Acceptance: fullscreen fills entire active screen edge-to-edge, no resize handles, content centered, leaves no gaps. Switch back to pill → pill returns to last user position/size.

Gotchas: `level = .floating` may sit below native fullscreen Spaces. May need `.statusBar` or `.popUpMenu` window level for true coverage. Test against fullscreen Safari side-by-side.

---

## W3 — Minimal: persist last size — ✅ DONE

Autosave name: `FloricFloatingLyricsWindow.minimal` (separate from pill). Set before first `setFrame`.

Today: minimal does not restore size across launches.

- `setFrameAutosaveName("FloricFloatingLyricsWindow.minimal")` separate from pill autosave (pill is fixed-size capsule, minimal is resizable).
- Ensure autosave runs after `setFrame` not before (Cocoa quirk — autosave reads frame from defaults only if name set BEFORE first setFrame).
- Size constraints: `contentMinSize`, `contentMaxSize` so user can't shrink below readable.
- On style switch pill→minimal: load saved minimal frame; minimal→pill: save minimal frame, apply pill default.

Acceptance: resize minimal, quit, relaunch → same size. Switch styles round-trip → minimal frame survives.

---

## W4 — Drop "click-through when inactive" — ✅ DONE

`Preferences.clickThrough` removed; legacy key purged at `init`. Pill uses internal `pillGrabActive` (Option-click toggle) replacing pref-driven escape hatch. Click-through is now a derived rule from `windowStyle`.

Today: pref toggles passthrough only when app inactive. User: not valid config.

- Decision: pill style = always click-through (per-pixel alpha hit-test stays for the pill silhouette). Minimal = never click-through (see W1). Fullscreen = always click-through except small dismiss/grab affordance.
- Remove `clickThrough` toggle from Settings entirely. Remove pref key (one-time migration: drop on read, ignore stored value).
- Audit `FloatingLyricsController` + `FloatingLyricsWindow` for `clickThrough` reads → replace with `windowStyle`-derived rule.
- Keep Option-click escape hatch for pill (existing toggle to grab the window for drag).

Acceptance: no toggle in Settings. Pill always passthrough except Option-held. Minimal always interactive. Fullscreen always passthrough.

Migration: `Preferences.init` — read + discard `Key.clickThrough`. No backwards-compat shim in code paths.

---

## Test gates (all 4)

- Snapshot matrix unchanged in dimensions but new fullscreen variant must render.
- Unit: `windowStyle == .minimal ⇒ effectiveClickThrough == false`.
- Manual: drag pill, click-through desktop icons, resize minimal, fullscreen across two displays.
- HIG/a11y review on diff (`/hig-check`).
