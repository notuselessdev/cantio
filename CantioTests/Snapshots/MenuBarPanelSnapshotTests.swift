import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
@testable import Cantio

@MainActor
final class MenuBarPanelSnapshotTests: XCTestCase {
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

    private func makePrefs() -> Preferences {
        let suite = "cantio.snapshot.menubar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = Preferences(defaults: defaults)
        prefs.accentHue = 220
        return prefs
    }

    private func panel(scheme: ColorScheme) -> some View {
        let prefs = makePrefs()
        let monitor = SpotifyMonitor()
        let store = LyricsStore()
        return MenuBarPanel(monitor: monitor, lyrics: store, prefs: prefs, onAppear: {})
            .frame(width: 268)
            .environment(\.colorScheme, scheme)
    }

    private let size = CGSize(width: 268, height: 360)

    func test_menuBarPanel_dark_emptyState() {
        assertSnapshot(of: host(panel(scheme: .dark), size: size),
                       as: .image(precision: 0.99, perceptualPrecision: 0.96))
    }

    func test_menuBarPanel_light_emptyState() {
        assertSnapshot(of: host(panel(scheme: .light), size: size),
                       as: .image(precision: 0.99, perceptualPrecision: 0.96))
    }
}
