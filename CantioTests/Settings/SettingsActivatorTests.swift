import XCTest
@testable import Cantio

final class SettingsActivatorTests: XCTestCase {
    private let singleScreen: [CGRect] = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
    private let dualScreen: [CGRect] = [
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
        CGRect(x: -1440, y: 200, width: 1440, height: 900),
    ]

    func test_shouldRecenter_frameFullyInsideScreen_returnsFalse() {
        let frame = CGRect(x: 100, y: 100, width: 560, height: 680)
        XCTAssertFalse(SettingsActivator.shouldRecenter(frame: frame, visibleFrames: singleScreen))
    }

    func test_shouldRecenter_frameEntirelyOffscreen_returnsTrue() {
        let frame = CGRect(x: 5000, y: 5000, width: 560, height: 680)
        XCTAssertTrue(SettingsActivator.shouldRecenter(frame: frame, visibleFrames: singleScreen))
    }

    func test_shouldRecenter_framePartiallyOverlapping_returnsFalse() {
        let frame = CGRect(x: 1800, y: 1000, width: 560, height: 680)
        XCTAssertFalse(SettingsActivator.shouldRecenter(frame: frame, visibleFrames: singleScreen))
    }

    func test_shouldRecenter_frameOnSecondaryScreen_returnsFalse() {
        let frame = CGRect(x: -1000, y: 400, width: 560, height: 680)
        XCTAssertFalse(SettingsActivator.shouldRecenter(frame: frame, visibleFrames: dualScreen))
    }

    func test_shouldRecenter_frameInGapBetweenScreens_returnsTrue() {
        let frame = CGRect(x: 2500, y: 400, width: 560, height: 680)
        XCTAssertTrue(SettingsActivator.shouldRecenter(frame: frame, visibleFrames: dualScreen))
    }

    func test_shouldRecenter_emptyScreenList_returnsTrue() {
        let frame = CGRect(x: 100, y: 100, width: 560, height: 680)
        XCTAssertTrue(SettingsActivator.shouldRecenter(frame: frame, visibleFrames: []))
    }
}
