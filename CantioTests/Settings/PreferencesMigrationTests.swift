import XCTest
import Carbon.HIToolbox
@testable import Cantio

@MainActor
final class PreferencesMigrationTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func test_init_legacyGlassPreset_mapsToFloatingGlass() {
        let d = makeDefaults()
        d.set("glass", forKey: "windowPreset")

        let prefs = Preferences(defaults: d)

        XCTAssertEqual(prefs.windowStyle, .floating)
        XCTAssertEqual(prefs.backgroundStyle, .glass)
    }

    func test_init_legacySolidPreset_mapsToFloatingSolid() {
        let d = makeDefaults()
        d.set("solid", forKey: "windowPreset")

        let prefs = Preferences(defaults: d)

        XCTAssertEqual(prefs.windowStyle, .floating)
        XCTAssertEqual(prefs.backgroundStyle, .solid)
    }

    func test_init_legacyMinimalPreset_mapsToFloatingGlass() {
        let d = makeDefaults()
        d.set("minimal", forKey: "windowPreset")

        let prefs = Preferences(defaults: d)

        XCTAssertEqual(prefs.windowStyle, .floating)
        XCTAssertEqual(prefs.backgroundStyle, .glass)
    }

    func test_init_legacyFullscreenPreset_mapsToFullscreenGlass() {
        let d = makeDefaults()
        d.set("fullscreen", forKey: "windowPreset")

        let prefs = Preferences(defaults: d)

        XCTAssertEqual(prefs.windowStyle, .fullscreen)
        XCTAssertEqual(prefs.backgroundStyle, .glass)
    }

    func test_init_noLegacyOrCurrent_defaultsToFloatingGlass() {
        let d = makeDefaults()

        let prefs = Preferences(defaults: d)

        XCTAssertEqual(prefs.windowStyle, .floating)
        XCTAssertEqual(prefs.backgroundStyle, .glass)
    }

    func test_init_explicitWindowStyle_winsOverLegacyPreset() {
        let d = makeDefaults()
        d.set("glass", forKey: "windowPreset")
        d.set("fullscreen", forKey: "windowStyle")

        let prefs = Preferences(defaults: d)

        XCTAssertEqual(prefs.windowStyle, .fullscreen)
    }

    func test_init_missingFontSize_defaultsToMedium() {
        let d = makeDefaults()

        let prefs = Preferences(defaults: d)

        XCTAssertEqual(prefs.fontSize, .medium)
    }

    func test_init_missingHideWhenPaused_defaultsToTrue() {
        let d = makeDefaults()

        let prefs = Preferences(defaults: d)

        XCTAssertTrue(prefs.hideWhenPaused)
    }

    func test_init_missingAlwaysOnTop_defaultsToTrue() {
        let d = makeDefaults()

        let prefs = Preferences(defaults: d)

        XCTAssertTrue(prefs.alwaysOnTop)
    }

    func test_init_missingWindowVisible_defaultsToTrue() {
        let d = makeDefaults()

        let prefs = Preferences(defaults: d)

        XCTAssertTrue(prefs.windowVisible)
    }

    func test_init_missingHotKey_defaultsToToggleDefault() {
        let d = makeDefaults()

        let prefs = Preferences(defaults: d)

        XCTAssertEqual(prefs.toggleHotKey, .defaultToggle)
    }

    func test_init_storedHotKey_roundTripsCodeAndModifiers() {
        let d = makeDefaults()
        let keyCode = UInt32(kVK_ANSI_Q)
        let mods = UInt32(cmdKey | shiftKey)
        d.set(Int(keyCode), forKey: "hotKey.keyCode")
        d.set(Int(mods), forKey: "hotKey.modifiers")

        let prefs = Preferences(defaults: d)

        XCTAssertEqual(prefs.toggleHotKey.keyCode, keyCode)
        XCTAssertEqual(prefs.toggleHotKey.modifiers, mods)
    }
}
