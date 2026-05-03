import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
@testable import Floric

@MainActor
final class PillCapsuleSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Set to true ONLY when re-recording. Default false → tests verify diffs.
        // Set to true ONLY when re-recording. Default false → tests verify diffs.
        // isRecording = true
    }

    private func host(_ view: some View, size: CGSize) -> NSView {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        return host
    }

    private func pill(tone: FL.Tone, bgStyle: Floric.BackgroundStyle) -> some View {
        let palette = FL.palette(tone: tone, hue: 220)
        let bg: Color = tone == .dark
            ? Color(.sRGB, red: 0.07, green: 0.08, blue: 0.10, opacity: 1)
            : Color(.sRGB, red: 0.93, green: 0.94, blue: 0.96, opacity: 1)
        return ZStack {
            bg
            PillCapsule(words: ["Hola", "mundo"],
                        palette: palette,
                        tone: tone,
                        bgStyle: bgStyle,
                        glassOpacity: 0.4)
        }
    }

    private let size = CGSize(width: 320, height: 80)

    func test_pillCapsule_dark_glass() {
        let view = pill(tone: FL.Tone.dark, bgStyle: Floric.BackgroundStyle.glass)
        assertSnapshot(of: host(view, size: size), as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    func test_pillCapsule_light_glass() {
        let view = pill(tone: FL.Tone.light, bgStyle: Floric.BackgroundStyle.glass)
        assertSnapshot(of: host(view, size: size), as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    func test_pillCapsule_dark_solid() {
        let view = pill(tone: FL.Tone.dark, bgStyle: Floric.BackgroundStyle.solid)
        assertSnapshot(of: host(view, size: size), as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }

    func test_pillCapsule_dark_glass_inactive() {
        // Variant kept for matrix completeness; PillCapsule has no `active` flag,
        // so we render the same content with reduced glassOpacity to differentiate.
        let palette = FL.palette(tone: .dark, hue: 220)
        let view = ZStack {
            Color(.sRGB, red: 0.07, green: 0.08, blue: 0.10, opacity: 1)
            PillCapsule(words: ["Hola", "mundo"],
                        palette: palette,
                        tone: FL.Tone.dark,
                        bgStyle: Floric.BackgroundStyle.glass,
                        glassOpacity: 0.0)
        }
        assertSnapshot(of: host(view, size: size), as: .image(precision: 0.99, perceptualPrecision: 0.97))
    }
}
