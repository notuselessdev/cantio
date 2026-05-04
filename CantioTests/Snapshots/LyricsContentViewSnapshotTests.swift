import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
@testable import Cantio

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

    private func makePrefs(style: Cantio.WindowStyle, bgStyle: Cantio.BackgroundStyle) -> Preferences {
        let suite = "cantio.snapshot.lyrics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = Preferences(defaults: defaults)
        prefs.windowStyle = style
        prefs.backgroundStyle = bgStyle
        prefs.accentHue = 220
        prefs.linesVisible = 3
        return prefs
    }

    private func makeView(style: Cantio.WindowStyle, bgStyle: Cantio.BackgroundStyle, scheme: ColorScheme) -> some View {
        let prefs = makePrefs(style: style, bgStyle: bgStyle)
        let monitor = SpotifyMonitor()
        let lyrics = LyricsStore()
        // Render the deterministic empty-state path: monitor.nowPlaying is nil
        // and lyrics.state is .idle (defaults). Avoids needing time-based mocks.
        return LyricsContentView(monitor: monitor, lyrics: lyrics, prefs: prefs)
            .environmentObject(PillHitTarget())
            .environment(\.colorScheme, scheme)
    }

    func test_lyricsContent_minimal_solid_light() {
        let view = makeView(style: Cantio.WindowStyle.minimal, bgStyle: Cantio.BackgroundStyle.solid, scheme: .light)
        assertSnapshot(of: host(view, size: CGSize(width: 520, height: 120)),
                       as: .image(precision: 0.99, perceptualPrecision: 0.96))
    }

    func test_lyricsContent_minimal_glass_dark() {
        let view = makeView(style: Cantio.WindowStyle.minimal, bgStyle: Cantio.BackgroundStyle.glass, scheme: .dark)
        assertSnapshot(of: host(view, size: CGSize(width: 520, height: 120)),
                       as: .image(precision: 0.99, perceptualPrecision: 0.96))
    }

    func test_lyricsContent_pill_glass_dark() {
        let view = makeView(style: Cantio.WindowStyle.pill, bgStyle: Cantio.BackgroundStyle.glass, scheme: .dark)
        assertSnapshot(of: host(view, size: CGSize(width: 520, height: 80)),
                       as: .image(precision: 0.99, perceptualPrecision: 0.96))
    }
}
