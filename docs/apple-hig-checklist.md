# Apple HIG Checklist — Cantio

Purpose: every UI change validated against this list before merge. Distilled from
Apple Human Interface Guidelines, focused on **macOS menu-bar utilities + floating
panels** (Cantio's two surfaces).

Use as: agent prompt material (HIG reviewer), PR review checklist, design test
matrix.

---

## 1. Materials & vibrancy

- [ ] Use `NSVisualEffectView` materials, not custom blur. Materials by surface:
  - Menu-bar dropdown → `.popover` or `.menu`
  - Floating panel (glass) → `.hudWindow` or `.popover`
  - Sidebar → `.sidebar`
  - Solid → palette color, no material
- [ ] `blendingMode = .behindWindow` for over-desktop; `.withinWindow` for layered controls.
- [ ] Set `state = .active` so material doesn't dim when window inactive.
- [ ] Host window MUST be `isOpaque = false` + `backgroundColor = .clear` for material to show.
- [ ] Honor `accessibilityReduceTransparency` — fall back to opaque palette.
- [ ] Honor `accessibilityIncreaseContrast` — bump stroke/text contrast.

## 2. Typography

- [ ] Use `Font.system(...)` (San Francisco) — never custom fonts for system UI.
- [ ] Sizes follow text styles when possible: `.body` 13pt, `.caption` 11pt, `.headline` 13 semibold.
- [ ] Tracking adjusted only for ALL-CAPS labels (~0.4–0.6 letter-spacing).
- [ ] Honor Dynamic Type when feasible (font sizes scale via prefs `fontSize`).
- [ ] Fullscreen lyrics IGNORE `prefs.fontSize` and auto-scale from container height (`height/8`, clamped 28...96pt; sub-line ~60% of active) — a 13" laptop and a 27" external both want different absolute sizes and the user shouldn't retune the slider on display change.
- [ ] Numerals in tabular contexts → `.monospacedDigit()`.
- [ ] Truncation: `.lineLimit(1) + .truncationMode(.middle)` for titles.

## 3. Color

- [ ] All colors derived from `FL.Palette` — no inline RGB except documented edge cases.
- [ ] Light + dark variants tested for every new view.
- [ ] Accent color respects user pref (`accentHue`) — never hardcoded blue.
- [ ] Contrast ≥ 4.5:1 for body text, ≥ 3:1 for large/UI elements (WCAG AA).
- [ ] Dim/faint text for non-essential info — never as primary control affordance.

## 4. Spacing & layout

- [ ] 8pt grid — paddings as multiples of 4 (preferred 8/12/16/20/24).
- [ ] Window corner radius 12pt (matches macOS standard).
- [ ] Capsule for pill / progress / tag shapes.
- [ ] Min hit target 28×28pt for clickable controls (44×44 ideal).
- [ ] Content insets respect window chrome — no overlap with traffic lights.

## 5. Motion

- [ ] Default animation: `.spring(response: 0.32, dampingFraction: 0.88)` for transitions; `.easeOut(0.22)` for property changes.
- [ ] Lyric line transitions: snappy crossfade with subtle directional offset (~4pt).
- [ ] Honor `accessibilityReduceMotion` — drop transitions to instant or pure crossfade.
- [ ] Never animate longer than 0.4s for routine state changes (karaoke = read-while-changing constraint).

## 6. Menu-bar specifics

- [ ] Status item: `Image(systemName:)` glyph at 14×14, optional truncated label.
- [ ] Menu opens via `MenuBarExtra(.window)` for custom UI; `.menu` for native list.
- [ ] Custom panel: rounded rect (11pt radius), VisualEffectBackground material, host window `isOpaque = false`.
- [ ] Hover state on every interactive row — not just active state.
- [ ] Keyboard shortcut hints (right-aligned, `palette.textFaint`, `tracking 0.4`).
- [ ] All actions reachable via keyboard (`SettingsLink`, `keyboardShortcut`).
- [ ] Cmd+Q from menu terminates app cleanly.

## 7. Floating panel specifics

- [ ] Borderless `NSWindow`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`.
- [ ] `isMovableByWindowBackground = true` for grab-anywhere drag.
- [ ] `hidesOnDeactivate = false` — must persist across app focus changes.
- [ ] `animationBehavior = .utilityWindow`.
- [ ] Disable `hasShadow` for capsule/fullscreen (custom silhouette); enable for rectangular chrome.
- [ ] Click-through (`ignoresMouseEvents`) togglable; visual indicator when active.
- [ ] Frame autosaved (`setFrameAutosaveName`) — position survives relaunch.

## 8. Settings window

- [ ] Use SwiftUI `Settings { }` scene + `SettingsLink`.
- [ ] App flips `NSApp.setActivationPolicy(.regular)` on Settings appear, back to `.accessory` on disappear (so it appears in cmd-tab).
- [ ] Single-pane preferred for ≤ 6 sections; tabs only when sections > 6 or distinct domains.
- [ ] Form rows: label left, control right, sub-text below label muted.
- [ ] Toggle/slider/segmented controls match system style — custom only for brand-critical surfaces.

## 9. Accessibility

- [ ] VoiceOver labels on every actionable view (`.accessibilityLabel`).
- [ ] `.accessibilityHint` for non-obvious actions.
- [ ] Custom controls expose `.accessibilityAddTraits(.isButton)` etc.
- [ ] Focus order matches visual order.
- [ ] Keyboard nav: Tab cycles controls; Esc dismisses popover.
- [ ] Honor `accessibilityReduceMotion` + `accessibilityReduceTransparency` + `accessibilityIncreaseContrast`.
- [ ] Color is never the only signal (pair with icon / text / shape).

## 10. Permissions & first-run

- [ ] Spotify Automation permission requested **lazily** on first need, not at launch.
- [ ] Denial state has clear recovery path: explain + "Open System Settings" button.
- [ ] No nag dialogs.
- [ ] Launch-at-login uses `SMAppService.mainApp` — no LaunchAgents plist.

## 11. Privacy & telemetry

- [ ] No analytics, no crash reporting, no network calls except documented (LRCLIB).
- [ ] State this honestly in Settings footer.

## 12. App Sandbox + Hardened Runtime

- [ ] Entitlements minimal: `com.apple.security.app-sandbox`, `com.apple.security.network.client` (lyrics), `com.apple.security.scripting-targets` (Spotify).
- [ ] Hardened Runtime enabled for distribution build.

## 13. Visual regression matrix (must pass per change)

For every UI change, validate across:

| Axis             | Values                                  |
| ---------------- | --------------------------------------- |
| `windowStyle`    | pill / minimal / fullscreen             |
| `backgroundStyle`| glass / solid (where applicable)        |
| `tone`           | light / dark / auto                     |
| `accentHue`      | sample 3 hues across spectrum           |
| `linesVisible`   | 1, 3, 5                                 |
| `fontSize`       | small, large                            |
| Reduce Transparency | on / off                             |
| Reduce Motion    | on / off                                |
| State            | playing / paused / no-music / no-permission |

Snapshot tests should cover this matrix automatically (see `docs/testing-strategy.md`).

---

## Quick reject list (auto-fail in HIG review)

- Custom blur instead of `NSVisualEffectView`.
- Inline RGB color outside palette.
- Hardcoded animation > 0.5s for routine state changes.
- Missing `accessibilityReduceMotion` / `accessibilityReduceTransparency` honor.
- New text without VoiceOver label.
- Hit target < 28pt.
- New control without keyboard equivalent.
- Network call to undocumented host.
- Menu-bar action > 1 step deep without shortcut.
