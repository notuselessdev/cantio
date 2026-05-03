# TODO — Liquid Glass

Status: **All milestones complete (L1–L5).** Runtime-gated `#available(macOS 26, *)` everywhere; macOS 14/15 uses existing `NSVisualEffectView` paths. Reduce Transparency + Increase Contrast both force `.off` regardless of pref.

Scope: native Liquid Glass material for pill mode + menubar panel. Settings-only configuration.
Owner files: `Cantio/MenuBarPanel.swift`, `Cantio/Floating/PillContent*.swift`, `Cantio/Settings/Preferences.swift`, `Cantio/Settings/PreferencesView.swift`, `Cantio/Theme/FL.Palette.swift` (or wherever materials live).

Reference: <https://claudeskills.club/skills/swiftui-liquid-glass-by-steipete>
API note: skill targets iOS 26 — same `.glassEffect()` API ships on **macOS 26 (Tahoe)**. Cantio deployment target = macOS 14. → MUST gate w/ `if #available(macOS 26, *)` + fallback to `NSVisualEffectView .hudWindow / .popover` (current impl).

---

## L1 — Replace `BackgroundStyle` w/ `GlassStyle` — ✅ DONE

Note: `BackgroundStyle` enum kept alive (still consumed by `LyricsContentView`/`FloatingLyricsController` for minimal/glass legacy branches). L1 added `GlassStyle` + `glassStyle` pref + one-shot migration that drops legacy `backgroundStyle` UserDefaults key. Future cleanup: full removal of `BackgroundStyle` once `LyricsContentView` glass branches all go through `effectiveGlassStyle`.

Today: `BackgroundStyle = { glass, solid }` applied to minimal only. Comment says pill + fullscreen ignore it.

New model — Liquid Glass is a **pill+menubar** concern, separate from minimal's solid/blur background:

```swift
enum GlassStyle: String, CaseIterable, Identifiable {
    case off       // no glass, no blur, palette-derived solid (or current visual-effect for menubar)
    case clear     // .glassEffect() default — translucent, no tint
    case tinted    // .glassEffect().tint(...) — accent-tinted glass
    var id: String { rawValue }
}
```

- Add `Preferences.glassStyle: GlassStyle` (default `.clear` on macOS 26+, forced `.off` on macOS 14/15 — runtime cap).
- Migration: read legacy `backgroundStyle` once at `init`. Map `.glass → .clear`, `.solid → .off`. Drop legacy key.
- `glassOpacity` pref: keep for `.tinted` strength. Range stays 0…1.
- Minimal mode background: detached from `glassStyle`. Minimal always renders palette-derived solid chrome (no glass, never). Document.
- Fullscreen: also no glass (per user — "not even in the table"). Render palette solid w/ low opacity, or transparent over wallpaper. Decide.

Acceptance: enum exists, default sane, migration drops legacy keys, minimal/fullscreen ignore `glassStyle` entirely.

---

## L2 — Pill: apply `.glassEffect()` — ✅ DONE

Today: pill uses `NSVisualEffectView .hudWindow` + custom palette tint.

- Pill content view `.glassEffect()` (clear) or `.glassEffect().tint(FL.Palette.accent.opacity(prefs.glassOpacity))` (tinted) when `prefs.glassStyle != .off` AND `#available(macOS 26, *)`.
- Wrap pill internals in `GlassEffectContainer` for unified silhouette (multiple text rows + capsule shape consistency).
- Modifier order per skill: layout → padding → background → **`.glassEffect()` last (after layout/visual)** → clipShape capsule → shadow.
- `.interactive()` on the pill ONLY if it has tap targets (Option-grab handle). Otherwise skip — perf + clarity penalty.
- Fallback path (`#unavailable`): existing `VisualEffectBackground(.hudWindow)` stays. Same call-site, branch internally.
- `glassStyle == .off`: render solid palette fill, no blur, no glass. (Useful for low-power, screen recordings, accessibility.)
- Honor `accessibilityReduceTransparency` — force `.off` regardless of pref (existing rule, keep). Honor `accessibilityIncreaseContrast` — switch to high-contrast palette fill.

Acceptance: pill on macOS 26+ shows Liquid Glass. Tinted variant picks up accent hue. Off variant solid. Reduce Transparency forces solid. macOS 14/15 still works via existing material.

Gotchas:
- `window.isOpaque = false` + `backgroundColor = .clear` still required so glass material reads desktop behind.
- `window.hasShadow = false` + `invalidateShadow()` still required (existing rule).
- `.glassEffect()` on borderless `NSWindow` may need extra ancestor-layer clearing — extend `WindowTransparencyApplier` if so. Test.

---

## L3 — Menubar panel: apply `.glassEffect()` — ✅ DONE

`.buttonStyle(.glass)` NOT applied — outer `GlassEffectContainer` already provides single unified silhouette; per-button glass would shatter that + double-stack on accent fills. Documented in agent report.

Today: `MenuBarPanel` uses `WindowTransparencyApplier` + `NSVisualEffectView .popover`.

- Same pattern as L2 — gated `.glassEffect()` on root panel content, fallback to current popover material.
- Wrap panel sections in `GlassEffectContainer` so player controls (see `menubar.md` M2) + lyric snippet share single glass silhouette rather than stacked layers.
- Buttons inside (play/pause/prev/next from M2): `.buttonStyle(.glass)` on macOS 26+, `.borderless` fallback.
- Honor same Reduce Transparency / Increase Contrast rules as L2.

Acceptance: menubar panel on macOS 26+ renders Liquid Glass. Buttons get `.glass` style. macOS 14/15 unchanged.

Sequencing: M2 (real player controls) lands first OR in same patch — `.buttonStyle(.glass)` only meaningful with real buttons.

---

## L4 — Settings UI — ✅ DONE

Picker rendered enabled-looking but `.disabled(true) + .opacity(0.5)` on macOS<26, with `PrefRow.sub = "Requires macOS 26 (Tahoe)"` matching existing PreferencesView idiom.

- Add Glass picker in `PreferencesView`: segmented or `Picker` w/ Off / Clear / Tinted.
- Show glass-opacity slider only when `.tinted` selected.
- Disable picker (or show "Requires macOS 26") banner when running on macOS 14/15 — pref forced `.off`.
- VoiceOver labels: "Liquid Glass style", "Off", "Clear", "Tinted", "Tint strength".
- Keyboard reachable.
- Live preview: pill + menubar update immediately.

Acceptance: 3 options visible, tint slider conditional, runtime gating works, accessibility labels present.

---

## L5 — Remove glass controls from menubar panel — ✅ DONE (verified clean by grep)

Per item M3 in `menubar.md`: theme picker leaves menubar. Same applies — `glassStyle` lives in Settings only. Verify menubar panel exposes none of these.

---

## Test gates

- Unit: migration `.glass → .clear`, `.solid → .off`. `glassStyle == .off` on macOS < 26 regardless of stored pref.
- Snapshot: pill × { off, clear, tinted } × tone(light/dark) × accentHue(2). Menubar panel × { off, clear, tinted } × tone(2). Gated to macOS 26 runners — skip / xfail on older.
- HIG/a11y: `/hig-check` on diff. Verify Reduce Transparency drops glass entirely.
- Manual: pill over busy desktop wallpaper, menubar over light + dark wallpaper, Spotify album art behind.

---

## Open questions

- macOS 26 deployment min vs runtime gating — keep min at 14, runtime branch only? **Recommend yes** — don't ship breakage on Sonoma/Sequoia users.
- Tinted variant: tint follows `prefs.accentHue` (recommended) or fixed neutral?
- Fullscreen glass: confirmed off per user. Document in `apple-hig-checklist.md` so future contributor doesn't re-add.
