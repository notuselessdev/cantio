import XCTest
@testable import Cantio

@MainActor
final class GlassStyleMigrationTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func test_init_legacyBackgroundStyleGlass_migratesToClearAndDropsLegacyKey() {
        let d = makeDefaults()
        d.set("glass", forKey: "backgroundStyle")

        let prefs = Preferences(defaults: d)

        XCTAssertEqual(prefs.glassStyle, Preferences.defaultGlassStyle)
        if #available(macOS 26, *) {
            XCTAssertEqual(prefs.glassStyle, .clear)
        } else {
            XCTAssertEqual(prefs.glassStyle, .off)
        }
        XCTAssertNil(d.string(forKey: "backgroundStyle"))
    }

    func test_init_legacyBackgroundStyleSolid_migratesToOffAndDropsLegacyKey() {
        let d = makeDefaults()
        d.set("solid", forKey: "backgroundStyle")

        let prefs = Preferences(defaults: d)

        XCTAssertEqual(prefs.glassStyle, .off)
        XCTAssertNil(d.string(forKey: "backgroundStyle"))
    }

    func test_init_noStoredValue_appliesDefaultForRuntime() {
        let d = makeDefaults()

        let prefs = Preferences(defaults: d)

        if #available(macOS 26, *) {
            XCTAssertEqual(prefs.glassStyle, .clear)
        } else {
            XCTAssertEqual(prefs.glassStyle, .off)
        }
    }

    func test_init_storedGlassStyle_winsOverLegacyBackgroundStyle() {
        let d = makeDefaults()
        d.set("solid", forKey: "backgroundStyle")
        d.set("clear", forKey: "glassStyle")

        let prefs = Preferences(defaults: d)

        XCTAssertEqual(prefs.glassStyle, .clear)
    }

    /// On pre-macOS-26 runtimes, `effectiveGlassStyle` MUST coerce to `.off`
    /// regardless of stored pref. On macOS 26+ this test asserts the pass-through.
    func test_effectiveGlassStyle_coercesToOffOnPreTahoe() {
        let d = makeDefaults()
        d.set("clear", forKey: "glassStyle")

        let prefs = Preferences(defaults: d)

        if #available(macOS 26, *) {
            XCTAssertEqual(prefs.effectiveGlassStyle, .clear)
        } else {
            XCTAssertEqual(prefs.effectiveGlassStyle, .off)
        }
    }

    func test_didSet_persistsGlassStyleChange() {
        let d = makeDefaults()
        let prefs = Preferences(defaults: d)

        prefs.glassStyle = .clear

        XCTAssertEqual(d.string(forKey: "glassStyle"), "clear")
    }

    /// `.tinted` was retired; existing prefs that stored it migrate to `.clear`.
    func test_init_legacyTintedStyle_migratesToClear() {
        let d = makeDefaults()
        d.set("tinted", forKey: "glassStyle")

        let prefs = Preferences(defaults: d)

        XCTAssertEqual(prefs.glassStyle, .clear)
    }
}
