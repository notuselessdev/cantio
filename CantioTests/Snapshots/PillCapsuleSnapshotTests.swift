import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
@testable import Cantio

// Snapshot matrix: tone={light,dark} × bgStyle={solid,glass} × wordLength={short,medium,long}
// Six base cases + the original inactive variant = 7 snapshots total.
// These tests lock in the fixed visual where shadow is scoped to the Capsule shape
// (not propagated to individual Text leaf views).

@MainActor
final class PillCapsuleSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Set to true ONLY when re-recording. Default false → tests verify diffs.
        // isRecording = true
    }

    private func host(_ view: some View, size: CGSize) -> NSView {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        return host
    }

    private func pill(
        tone: FL.Tone,
        bgStyle: Cantio.BackgroundStyle,
        words: [String]
    ) -> some View {
        let palette = FL.palette(tone: tone, hue: 220)
        let bg: Color = tone == .dark
            ? Color(.sRGB, red: 0.07, green: 0.08, blue: 0.10, opacity: 1)
            : Color(.sRGB, red: 0.93, green: 0.94, blue: 0.96, opacity: 1)
        return ZStack {
            bg
            PillCapsule(words: words,
                        palette: palette,
                        tone: tone,
                        bgStyle: bgStyle)
        }
    }

    // Wide canvas so even 8-word lines render without clipping.
    // NOTE: New tests use 480×80. The four original tests below use 320×80 to avoid
    // re-recording their committed baselines — snapshot library detects size mismatches.
    private let size = CGSize(width: 480, height: 80)
    private let legacySize = CGSize(width: 320, height: 80)

    // MARK: - Short words (1 word)

    func test_pillCapsule_dark_glass_short() {
        let view = pill(tone: .dark, bgStyle: .glass, words: ["Hi"])
        assertSnapshot(of: host(view, size: size),
                       as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    func test_pillCapsule_light_glass_short() {
        let view = pill(tone: .light, bgStyle: .glass, words: ["Hi"])
        assertSnapshot(of: host(view, size: size),
                       as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    func test_pillCapsule_dark_solid_short() {
        let view = pill(tone: .dark, bgStyle: .solid, words: ["Hi"])
        assertSnapshot(of: host(view, size: size),
                       as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    func test_pillCapsule_light_solid_short() {
        let view = pill(tone: .light, bgStyle: .solid, words: ["Hi"])
        assertSnapshot(of: host(view, size: size),
                       as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    // MARK: - Medium words (4 words)

    func test_pillCapsule_dark_glass_medium() {
        let view = pill(tone: .dark, bgStyle: .glass, words: ["Hold", "on", "to", "me"])
        assertSnapshot(of: host(view, size: size),
                       as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    func test_pillCapsule_light_glass_medium() {
        let view = pill(tone: .light, bgStyle: .glass, words: ["Hold", "on", "to", "me"])
        assertSnapshot(of: host(view, size: size),
                       as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    func test_pillCapsule_dark_solid_medium() {
        let view = pill(tone: .dark, bgStyle: .solid, words: ["Hold", "on", "to", "me"])
        assertSnapshot(of: host(view, size: size),
                       as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    func test_pillCapsule_light_solid_medium() {
        let view = pill(tone: .light, bgStyle: .solid, words: ["Hold", "on", "to", "me"])
        assertSnapshot(of: host(view, size: size),
                       as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    // MARK: - Long words (8 words)

    func test_pillCapsule_dark_glass_long() {
        let view = pill(tone: .dark, bgStyle: .glass,
                        words: ["Can't", "stop", "won't", "stop", "moving", "to", "the", "beat"])
        assertSnapshot(of: host(view, size: size),
                       as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    func test_pillCapsule_light_glass_long() {
        let view = pill(tone: .light, bgStyle: .glass,
                        words: ["Can't", "stop", "won't", "stop", "moving", "to", "the", "beat"])
        assertSnapshot(of: host(view, size: size),
                       as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    func test_pillCapsule_dark_solid_long() {
        let view = pill(tone: .dark, bgStyle: .solid,
                        words: ["Can't", "stop", "won't", "stop", "moving", "to", "the", "beat"])
        assertSnapshot(of: host(view, size: size),
                       as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    func test_pillCapsule_light_solid_long() {
        let view = pill(tone: .light, bgStyle: .solid,
                        words: ["Can't", "stop", "won't", "stop", "moving", "to", "the", "beat"])
        assertSnapshot(of: host(view, size: size),
                       as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    // MARK: - Original tests (kept at legacy 320×80 canvas to preserve committed baselines)

    func test_pillCapsule_dark_glass() {
        let view = pill(tone: .dark, bgStyle: .glass, words: ["Hola", "mundo"])
        assertSnapshot(of: host(view, size: legacySize),
                       as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    func test_pillCapsule_light_glass() {
        let view = pill(tone: .light, bgStyle: .glass, words: ["Hola", "mundo"])
        assertSnapshot(of: host(view, size: legacySize),
                       as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    func test_pillCapsule_dark_solid() {
        let view = pill(tone: .dark, bgStyle: .solid, words: ["Hola", "mundo"])
        assertSnapshot(of: host(view, size: legacySize),
                       as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    func test_pillCapsule_dark_glass_inactive() {
        let palette = FL.palette(tone: .dark, hue: 220)
        let view = ZStack {
            Color(.sRGB, red: 0.07, green: 0.08, blue: 0.10, opacity: 1)
            PillCapsule(words: ["Hola", "mundo"],
                        palette: palette,
                        tone: .dark,
                        bgStyle: .glass)
        }
        assertSnapshot(of: host(view, size: legacySize),
                       as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }
}
