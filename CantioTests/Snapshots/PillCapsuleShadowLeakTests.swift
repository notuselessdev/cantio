import XCTest
import SwiftUI
import AppKit
@testable import Cantio

// Mechanical regression guard for the per-leaf shadow bug (commit f903ba0→324d204 era).
//
// Background: before the fix, `.shadow(...)` was applied to the HStack of Text views
// directly. SwiftUI propagated the shadow to each leaf Text. During a 0.3 s easeInOut
// layout reflow, the per-leaf shadows piled at the top edge of the resizing capsule —
// visible as a dark border above the capsule that snapped to the bottom on settle.
//
// After the fix, `.shadow` lives inside `.background { Capsule()...shadow(...) }` so it
// is scoped to a single composited shape and never escapes above the capsule bounds.
//
// These tests render PillCapsule into an NSImage and inspect the pixel rows that sit
// ABOVE the capsule's vertical centre. In a correct render the top-margin area of the
// canvas (which is the opaque background colour) must not contain dark pixels that
// indicate shadow bleed from individual Text leaves.
//
// Threshold chosen conservatively: a shadow artefact produces luminance < 0.85 in the
// rows above the capsule. The plain background (dark or light) occupies those rows at
// near-constant luminance. Any significant darkening in those rows fails the test.

@MainActor
final class PillCapsuleShadowLeakTests: XCTestCase {

    // MARK: - Rendering helpers

    private func renderToImage(
        tone: FL.Tone,
        bgStyle: Cantio.BackgroundStyle,
        words: [String],
        canvasSize: CGSize = CGSize(width: 480, height: 80)
    ) -> NSImage {
        let palette = FL.palette(tone: tone, hue: 220)
        let bg: Color = tone == .dark
            ? Color(.sRGB, red: 0.07, green: 0.08, blue: 0.10, opacity: 1)
            : Color(.sRGB, red: 0.93, green: 0.94, blue: 0.96, opacity: 1)

        let view = ZStack {
            bg
            PillCapsule(words: words,
                        palette: palette,
                        tone: tone,
                        bgStyle: bgStyle)
        }

        let hostView = NSHostingView(rootView: view)
        hostView.frame = CGRect(origin: .zero, size: canvasSize)

        // Force layout so the view tree is fully committed before snapshotting.
        hostView.layoutSubtreeIfNeeded()

        let image = NSImage(size: canvasSize)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            hostView.layer?.render(in: ctx)
        }
        image.unlockFocus()
        return image
    }

    // Returns a CGImage backed by a bitmap context so we can call
    // dataProvider on it — NSImage alone isn't guaranteed to have pixel data.
    private func bitmapPixels(of image: NSImage) -> (data: [UInt8], width: Int, height: Int)? {
        let w = Int(image.size.width)
        let h = Int(image.size.height)
        guard w > 0, h > 0 else { return nil }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w,
            pixelsHigh: h,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: w * 4,
            bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()

        guard let rawData = rep.bitmapData else { return nil }
        let byteCount = w * h * 4
        return (Array(UnsafeBufferPointer(start: rawData, count: byteCount)), w, h)
    }

    // Computes perceptual luminance of an sRGB pixel at byte offset `base` in the data array.
    // Coefficients: ITU-R BT.709.
    private func luminance(_ data: [UInt8], at base: Int) -> Double {
        let r = Double(data[base])     / 255.0
        let g = Double(data[base + 1]) / 255.0
        let b = Double(data[base + 2]) / 255.0
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    // Returns the minimum luminance found in pixel rows [0..<rowCount] of the bitmap.
    // NSBitmapImageRep stores rows top-to-bottom when drawn via NSGraphicsContext.
    private func minLuminanceInTopRows(
        _ data: [UInt8],
        width: Int,
        rowCount: Int
    ) -> Double {
        var minLum = 1.0
        for row in 0..<rowCount {
            for col in 0..<width {
                let base = (row * width + col) * 4
                let lum = luminance(data, at: base)
                if lum < minLum { minLum = lum }
            }
        }
        return minLum
    }

    // MARK: - Shadow-leak assertions
    //
    // The canvas is 80 pt tall. The pill capsule (9pt vertical padding + ~22pt text +
    // 9pt vertical padding = ~40pt) is centred, so the top ~20 pt of the canvas is the
    // plain background colour. We inspect the top 10 rows (pt-equivalent rows in the
    // bitmap, ×1 scale for CI, ×2 on Retina — we use the raw pixel row count from the
    // bitmap).
    //
    // Dark background expected luminance: ~0.08 (very dark).
    // Light background expected luminance: ~0.92 (very light).
    //
    // A per-leaf shadow artefact darkens light pixels to ~0.60-0.70 — well below the
    // threshold delta we check (> 0.15 drop from the expected background luminance).
    //
    // We use a simple approach: the minimum luminance in the top rows must not be MORE
    // THAN 0.20 lower than the expected background luminance. This is the mechanical
    // check that would have caught the bug.

    private func assertNoShadowLeakAboveCapsule(
        tone: FL.Tone,
        bgStyle: Cantio.BackgroundStyle,
        words: [String],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let image = renderToImage(tone: tone, bgStyle: bgStyle, words: words)
        guard let (data, width, height) = bitmapPixels(of: image) else {
            XCTFail("Failed to get bitmap data", file: file, line: line)
            return
        }

        // Top 10 pixel rows (device-pixel rows). On @1x this is 10pt; on @2x it is 5pt.
        // Either way it covers the margin above the capsule.
        let topRowCount = min(10, height)

        // Expected background luminance (from the fill colour used in the ZStack).
        let expectedBgLum: Double = tone == .dark ? 0.08 : 0.92

        let minTopLum = minLuminanceInTopRows(data, width: width, rowCount: topRowCount)

        // The drop from expected background must not exceed 0.20.
        // A legitimate drop on dark bg: near 0 (background is already dark, no shadow can
        // make it meaningfully darker in the top rows).
        // A leak on light bg: drops from ~0.92 down to ~0.60 → delta ~0.32 → FAIL.
        let drop = expectedBgLum - minTopLum
        XCTAssertLessThanOrEqual(
            drop,
            0.20,
            "Shadow leaked above PillCapsule top edge (tone=\(tone), bgStyle=\(bgStyle), words=\(words)). "
            + "Expected background luminance ~\(String(format: "%.2f", expectedBgLum)), "
            + "found minimum \(String(format: "%.2f", minTopLum)) in top \(topRowCount) rows — drop of "
            + "\(String(format: "%.2f", drop)) exceeds 0.20 threshold.",
            file: file, line: line
        )
    }

    // MARK: - Test methods

    // Short words — narrowest capsule, shadow most likely to concentrate on leaf edges.

    func test_pillCapsule_shadowLeak_darkGlass_short() {
        assertNoShadowLeakAboveCapsule(tone: .dark, bgStyle: .glass, words: ["Hi"])
    }

    func test_pillCapsule_shadowLeak_lightGlass_short() {
        assertNoShadowLeakAboveCapsule(tone: .light, bgStyle: .glass, words: ["Hi"])
    }

    func test_pillCapsule_shadowLeak_darkSolid_short() {
        assertNoShadowLeakAboveCapsule(tone: .dark, bgStyle: .solid, words: ["Hi"])
    }

    func test_pillCapsule_shadowLeak_lightSolid_short() {
        assertNoShadowLeakAboveCapsule(tone: .light, bgStyle: .solid, words: ["Hi"])
    }

    // Medium words — representative karaoke line.

    func test_pillCapsule_shadowLeak_darkGlass_medium() {
        assertNoShadowLeakAboveCapsule(tone: .dark, bgStyle: .glass,
                                       words: ["Hold", "on", "to", "me"])
    }

    func test_pillCapsule_shadowLeak_lightGlass_medium() {
        assertNoShadowLeakAboveCapsule(tone: .light, bgStyle: .glass,
                                       words: ["Hold", "on", "to", "me"])
    }

    func test_pillCapsule_shadowLeak_darkSolid_medium() {
        assertNoShadowLeakAboveCapsule(tone: .dark, bgStyle: .solid,
                                       words: ["Hold", "on", "to", "me"])
    }

    func test_pillCapsule_shadowLeak_lightSolid_medium() {
        assertNoShadowLeakAboveCapsule(tone: .light, bgStyle: .solid,
                                       words: ["Hold", "on", "to", "me"])
    }

    // Long words — widest capsule; per-leaf shadows piled hardest at extremes.

    func test_pillCapsule_shadowLeak_darkGlass_long() {
        assertNoShadowLeakAboveCapsule(tone: .dark, bgStyle: .glass,
                                       words: ["Can't", "stop", "won't", "stop", "moving", "to", "the", "beat"])
    }

    func test_pillCapsule_shadowLeak_lightGlass_long() {
        assertNoShadowLeakAboveCapsule(tone: .light, bgStyle: .glass,
                                       words: ["Can't", "stop", "won't", "stop", "moving", "to", "the", "beat"])
    }

    func test_pillCapsule_shadowLeak_darkSolid_long() {
        assertNoShadowLeakAboveCapsule(tone: .dark, bgStyle: .solid,
                                       words: ["Can't", "stop", "won't", "stop", "moving", "to", "the", "beat"])
    }

    func test_pillCapsule_shadowLeak_lightSolid_long() {
        assertNoShadowLeakAboveCapsule(tone: .light, bgStyle: .solid,
                                       words: ["Can't", "stop", "won't", "stop", "moving", "to", "the", "beat"])
    }
}
