import XCTest
@testable import Floric

@MainActor
final class EffectiveClickThroughTests: XCTestCase {
    func test_effectiveClickThrough_minimal_isFalse() {
        XCTAssertFalse(FloatingLyricsController.effectiveClickThrough(for: .minimal))
    }

    func test_effectiveClickThrough_pill_isTrue() {
        XCTAssertTrue(FloatingLyricsController.effectiveClickThrough(for: .pill))
    }

    func test_effectiveClickThrough_fullscreen_isTrue() {
        XCTAssertTrue(FloatingLyricsController.effectiveClickThrough(for: .fullscreen))
    }
}
