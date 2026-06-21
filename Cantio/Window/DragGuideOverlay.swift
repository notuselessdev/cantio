import AppKit
import SwiftUI

/// Full-screen, click-through overlay that draws Raycast-style dashed
/// alignment guides while the pill is being dragged. The guides form the
/// pill's default "parking slot": two vertical rulers (its left/right edges
/// at rest) and two horizontal rulers (its top/bottom edges). The pill
/// magnetizes into the slot; the matching pair brightens once snapped.
@MainActor
final class DragGuideOverlay {
    private var window: NSPanel?

    /// Show / refresh the overlay on `screen`. `slot` is the pill's default
    /// frame in AppKit screen coords; `tint` (palette accent) colors the
    /// rulers once their axis snaps.
    func update(screen: NSScreen, slot: NSRect,
                snapX: Bool, snapY: Bool, tint: Color) {
        let frame = screen.frame
        let panel = window ?? makePanel(frame: frame)
        window = panel
        if panel.frame != frame { panel.setFrame(frame, display: false) }

        if let host = panel.contentView as? NSHostingView<DragGuideView> {
            host.rootView = makeView(frame: frame, slot: slot,
                                     snapX: snapX, snapY: snapY, tint: tint)
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        window?.orderOut(nil)
    }

    /// Convert the AppKit-space slot into an overlay-local (SwiftUI top-left)
    /// rect for the dashed box.
    private func makeView(frame: NSRect, slot: NSRect,
                          snapX: Bool, snapY: Bool, tint: Color) -> DragGuideView {
        let local = CGRect(x: slot.minX - frame.minX,
                           y: frame.maxY - slot.maxY,
                           width: slot.width, height: slot.height)
        return DragGuideView(box: local, snapX: snapX, snapY: snapY, tint: tint)
    }

    private func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: makeView(
            frame: frame, slot: frame, snapX: false, snapY: false, tint: .accentColor))
        panel.contentView = host
        return panel
    }
}

/// Four full-length dashed rulers marking the pill's default parking slot, in
/// overlay-local (top-left origin) coordinates: two vertical lines (the slot's
/// left/right edges) spanning top-to-bottom, two horizontal lines (top/bottom
/// edges) spanning side-to-side. The vertical pair lights on `snapX`, the
/// horizontal pair on `snapY`.
struct DragGuideView: View {
    let box: CGRect
    let snapX: Bool
    let snapY: Bool
    let tint: Color

    private let dash = StrokeStyle(lineWidth: 1.5, dash: [6, 5])

    var body: some View {
        ZStack {
            // Vertical rulers (left + right edges) — full height.
            ruler(snapped: snapX) { p, size in
                p.move(to: CGPoint(x: box.minX, y: 0)); p.addLine(to: CGPoint(x: box.minX, y: size.height))
                p.move(to: CGPoint(x: box.maxX, y: 0)); p.addLine(to: CGPoint(x: box.maxX, y: size.height))
            }
            // Horizontal rulers (top + bottom edges) — full width.
            ruler(snapped: snapY) { p, size in
                p.move(to: CGPoint(x: 0, y: box.minY)); p.addLine(to: CGPoint(x: size.width, y: box.minY))
                p.move(to: CGPoint(x: 0, y: box.maxY)); p.addLine(to: CGPoint(x: size.width, y: box.maxY))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func ruler(snapped: Bool,
                       _ build: @escaping (inout Path, CGSize) -> Void) -> some View {
        GeometryReader { geo in
            Path { p in build(&p, geo.size) }
                // Dark underlay keeps the dashes legible over light wallpaper.
                .stroke(Color.black.opacity(0.25), style: dash)
                .overlay(
                    Path { p in build(&p, geo.size) }
                        .stroke(snapped ? tint : Color.white.opacity(0.75), style: dash)
                )
                .opacity(snapped ? 1 : 0.9)
        }
    }
}
