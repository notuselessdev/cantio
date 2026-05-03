import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
@testable import Floric

@MainActor
final class LyricsContentViewSnapshotTests: XCTestCase {
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

    private func makePrefs(style: Floric.WindowStyle, bgStyle: Floric.BackgroundStyle, tone: Floric.Tone) -> Preferences {
        let suite = "floric.snapshot.lyrics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = Preferences(defaults: defaults)
        prefs.windowStyle = style
        prefs.backgroundStyle = bgStyle
        prefs.tone = tone
        prefs.accentHue = 220
        prefs.linesVisible = 3
        return prefs
    }

    private func makeView(style: Floric.WindowStyle, bgStyle: Floric.BackgroundStyle, tone: Floric.Tone) -> some View {
        let prefs = makePrefs(style: style, bgStyle: bgStyle, tone: tone)
        let monitor = SpotifyMonitor()
        let lyrics = LyricsStore()
        // Render the deterministic empty-state path: monitor.nowPlaying is nil
        // and lyrics.state is .idle (defaults). Avoids needing time-based mocks.
        return LyricsContentView(monitor: monitor, lyrics: lyrics, prefs: prefs)
    }

    func test_lyricsContent_minimal_solid_light() {
        let view = makeView(style: Floric.WindowStyle.minimal, bgStyle: Floric.BackgroundStyle.solid, tone: Floric.Tone.light)
        assertSnapshot(of: host(view, size: CGSize(width: 520, height: 120)),
                       as: .image(precision: 0.99, perceptualPrecision: 0.96))
    }

    func test_lyricsContent_minimal_glass_dark() {
        let view = makeView(style: Floric.WindowStyle.minimal, bgStyle: Floric.BackgroundStyle.glass, tone: Floric.Tone.dark)
        assertSnapshot(of: host(view, size: CGSize(width: 520, height: 120)),
                       as: .image(precision: 0.99, perceptualPrecision: 0.96))
    }

    func test_lyricsContent_pill_glass_dark() {
        let view = makeView(style: Floric.WindowStyle.pill, bgStyle: Floric.BackgroundStyle.glass, tone: Floric.Tone.dark)
        assertSnapshot(of: host(view, size: CGSize(width: 520, height: 80)),
                       as: .image(precision: 0.99, perceptualPrecision: 0.96))
    }
}
