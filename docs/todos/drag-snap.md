# TODO — Drag snap + alignment guides

Scope: Raycast-style alignment guides + magnetic snap for floating lyrics window during drag. Bottom-center primary anchor (lyrics naturally sit low).
Owner files: `Floric/Floating/FloatingLyricsController.swift`, `Floric/Floating/FloatingLyricsWindow.swift`, possibly new `Floric/Floating/DragSnapOverlay.swift`.

Reference: Raycast shows dashed crosshair at top-center with magnetic pull radius ~40pt while dragging.

---

## D1 — Detect drag start / move / end

- Hook into `NSWindow` move events. Two options:
  - Override `mouseDragged` / `mouseUp` on borderless `NSWindow` subclass (already custom). Set `inFlight` flag.
  - Observe `NSWindow.didMoveNotification` — fires on every move tick, no start/end signal. Pair with `NSEvent.addLocalMonitorForEvents(.leftMouseDown / .leftMouseUp)` to bracket.
- Recommendation: subclass route — already have `FloatingLyricsWindow`. Override `mouseDown` (start), `mouseDragged` (update), `mouseUp` (end).
- `isMovableByWindowBackground = true` (already set) — verify drag still works after override; call `super` to preserve.

Acceptance: controller knows `dragState ∈ {.idle, .dragging(currentFrame)}`.

---

## D2 — Compute target anchors

Anchor set per active `NSScreen` (the one cursor lives on, not necessarily window's current screen):

- `bottomCenter` — `(screen.visibleFrame.midX, screen.visibleFrame.minY + bottomInset)`. Primary for pill (lyrics live there).
- `topCenter` — `(screen.visibleFrame.midX, screen.visibleFrame.maxY - topInset)`. Secondary, less common but useful.
- Optional later: `center`, screen edges. Defer — start minimal.

`bottomInset`: ~80pt above Dock / screen edge. Pull from `screen.visibleFrame` directly so Dock auto-handled.

Pull radius: 40pt (matches Raycast feel).

---

## D3 — Snap math

Each `mouseDragged` tick:
1. Window's would-be bottom-center point.
2. Distance to nearest anchor.
3. If `< pullRadius` → override window origin so bottom-center == anchor. Else free.
4. Resistance curve optional (linear ease as approach radius). Start with hard snap inside radius — simpler, ship first.
5. Track `isSnapped` for haptic / visual feedback.

Edge: multi-monitor — compute against screen mouse cursor lives on. Recompute on every tick (cursor crossings).

Reduce Motion: skip resistance easing, hard snap only.

---

## D4 — Dashed guide overlay

Borderless transparent overlay window per active screen, level `.floating`, `ignoresMouseEvents = true`, shown only during `.dragging`.

Render:
- Vertical dashed line through anchor X, faint (palette `.secondary` 0.5 alpha), full screen height.
- Horizontal dashed marker at anchor Y, ~80pt wide centered on anchor X.
- Highlight (brighter + thicker) when `isSnapped == true`.

SwiftUI:
```swift
Path { p in
    p.move(to: CGPoint(x: anchorX, y: 0))
    p.addLine(to: CGPoint(x: anchorX, y: screenHeight))
}
.stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
.foregroundStyle(FL.Palette.secondary.opacity(isSnapped ? 0.9 : 0.4))
```

Lifecycle:
- Created lazily on first drag, retained on controller.
- `orderFront` on drag start, `orderOut` on drag end.
- Tear down on screen-config change → recreate next drag.
- DO NOT show when Reduce Motion off + Reduce Transparency on? — overlay is functional, not decorative. Keep visible always while dragging. Reduce Transparency: drop dashed style → solid 1pt line.

---

## D5 — Apply only to pill style

- Minimal = real chrome window, native window snap (left/right halves) handled by macOS Stage Manager / Magnet. Don't fight it. **Skip overlay for minimal.**
- Fullscreen = no drag (window pinned to screen). N/A.
- Pill = primary target. Apply.

Gate in controller: `guard prefs.windowStyle == .pill else { return }`.

---

## D6 — Settings toggle (optional, default on)

`Preferences.snapToScreenEdges: Bool = true`. Settings → Behavior → "Magnetic alignment while dragging".

VoiceOver: "Magnetic alignment guides". Keyboard reachable.

If user disables → no overlay, no snap, free drag.

---

## Test gates

- Unit (pure):
  - `nearestAnchor(point: CGPoint, anchors: [CGPoint], radius: CGFloat) -> CGPoint?`
  - Test: in radius → returns anchor. Outside → nil. Multi-anchor → nearest one.
- Snapshot: overlay on / off, snapped / unsnapped variants. Synthetic screen frame.
- Manual: drag pill across single + multi-monitor, with + without Dock visible, Reduce Motion on, Reduce Transparency on.
- HIG: dashed-guide contrast against busy wallpaper. Confirm visible on both light + dark backgrounds.

---

## Open questions

- Pull radius value: 40pt feel right? Test with users (or self) before locking.
- Snap to current screen of cursor vs current screen of window? Cursor wins (matches Raycast). Confirm.
- Top-center anchor worth shipping in v1? Defer — start with bottom-center only, expand if asked.
- Animate window into snap (spring) vs hard? Hard for v1, spring later if jittery.
