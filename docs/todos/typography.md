# TODO — Font size scale

Scope: lyric line + sub-line typography across pill / minimal / fullscreen.
Owner files: `Floric/Settings/Preferences.swift` (FontSize enum), `Floric/Floating/LyricsContentView.swift` (or equivalent renderer), `Floric/Settings/PreferencesView.swift`.

---

## T1 — Expand FontSize to 5 steps

Today: `FontSize` = `.small (0)`, `.medium (1)`, `.large (2)`, `.xlarge (3)`. Already 4 — add `.xsmall`.

```swift
enum FontSize: Int, CaseIterable, Identifiable, Comparable {
    case xsmall = 0
    case small = 1
    case medium = 2
    case large = 3
    case xlarge = 4
}
```

- Renumber raw values OR keep raw values and prepend `xsmall = -1` to avoid migration. **Recommendation: keep existing raws, add `xsmall = -1`** — zero migration risk for stored prefs.
- Add display labels: "Extra Small", "Small", "Medium", "Large", "Extra Large".
- Add point sizes (lyric / sub):
  - xsmall: 14 / 10
  - small: 18 / 12 (existing)
  - medium: 22 / 14 (existing)
  - large: 26 / 16 (existing)
  - xlarge: pick — suggest 32 / 18.
- Default unchanged: `.medium`.

Acceptance: 5 cases, all `CaseIterable`-iterated in Settings picker. Existing stored value (small/medium/large/xlarge) loads unchanged.

---

## T2 — Settings UI

- Replace existing font-size control with 5-option segmented picker OR `Picker` menu.
- VoiceOver label "Lyric font size" + per-option labels.
- Keyboard reachable.
- Live preview: changing font-size updates floating window in real time (already wired via `@Published`? — verify).

Acceptance: 5 options visible, selected option persists, floating window updates immediately.

---

## T3 — Fullscreen size scaling

Fullscreen mode (see `windows.md` W2) needs larger absolute sizes since window is huge.

- Decide: fullscreen ignores user FontSize and uses dynamic size (e.g. `screen.height / N`)? OR multiplies user FontSize by 1.5–2×?
- Recommendation: dynamic — fullscreen lyrics auto-scale to fill, font-size pref ignored when `windowStyle == .fullscreen`. Document in `apple-hig-checklist.md`.
- If kept user-controlled: extend the 5 sizes to fullscreen-specific values.

Acceptance: fullscreen lyrics readable across 13" laptop and 27" external without manual tweak.

---

## Test gates

- Unit: `FontSize.allCases.count == 5`, point sizes monotonic.
- Snapshot: matrix gains 2 new font-size dimensions (xsmall, xlarge) — check matrix size in `testing-strategy.md` §13. Currently small + large; expanding to xsmall + xlarge ≈ doubles cells. Decide if matrix uses subset (xsmall + xlarge only) to keep total ≈60.
- Manual: pill / minimal / fullscreen × all 5 sizes.
