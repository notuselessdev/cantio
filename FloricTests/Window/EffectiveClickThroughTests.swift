import XCTest
import AppKit
@testable import Floric

@MainActor
final class EffectiveClickThroughTests: XCTestCase {
    func test_effectiveClickThrough_minimal_isFalse() {
        XCTAssertFalse(FloatingLyricsController.effectiveClickThrough(for: .minimal))
    }

    func test_effectiveClickThrough_pill_isTrue() {
        XCTAssertTrue(FloatingLyricsController.effectiveClickThrough(for: .pill))
    }

    func test_effectiveClickThrough_fullscreen_isFalse() {
        XCTAssertFalse(FloatingLyricsController.effectiveClickThrough(for: .fullscreen))
    }

    // MARK: - Click vs drag classifier

    private func mouseEvent(at point: NSPoint, type: NSEvent.EventType) -> NSEvent {
        // Use a synthesized window-coordinate event. `mouseEvent` takes
        // window/window coordinates relative to a window — passing a nil
        // window with a synthesized location is sufficient because the
        // classifier only inspects `locationInWindow`.
        return NSEvent.mouseEvent(with: type,
                                  location: point,
                                  modifierFlags: [],
                                  timestamp: 0,
                                  windowNumber: 0,
                                  context: nil,
                                  eventNumber: 0,
                                  clickCount: 1,
                                  pressure: 1)!
    }

    func test_shouldStartDrag_belowThreshold_returnsFalse() {
        let begin = mouseEvent(at: NSPoint(x: 100, y: 100), type: .leftMouseDown)
        let upClose = mouseEvent(at: NSPoint(x: 102, y: 101), type: .leftMouseUp)
        XCTAssertFalse(FloatingLyricsController.shouldStartDrag(
            beginEvent: begin, currentEvent: upClose, thresholdPoints: 4))
    }

    func test_shouldStartDrag_atThreshold_returnsTrue() {
        let begin = mouseEvent(at: NSPoint(x: 100, y: 100), type: .leftMouseDown)
        // 4pt away exactly (3-4-5 triangle scaled: dx=4, dy=0 → dist=4).
        let drag = mouseEvent(at: NSPoint(x: 104, y: 100), type: .leftMouseDragged)
        XCTAssertTrue(FloatingLyricsController.shouldStartDrag(
            beginEvent: begin, currentEvent: drag, thresholdPoints: 4))
    }

    func test_shouldStartDrag_aboveThreshold_returnsTrue() {
        let begin = mouseEvent(at: NSPoint(x: 100, y: 100), type: .leftMouseDown)
        let drag = mouseEvent(at: NSPoint(x: 120, y: 130), type: .leftMouseDragged)
        XCTAssertTrue(FloatingLyricsController.shouldStartDrag(
            beginEvent: begin, currentEvent: drag, thresholdPoints: 4))
    }

    func test_shouldStartDrag_diagonalBelowThreshold_returnsFalse() {
        let begin = mouseEvent(at: NSPoint(x: 50, y: 50), type: .leftMouseDown)
        // dx=2, dy=2 → dist≈2.83, below 4pt threshold.
        let drag = mouseEvent(at: NSPoint(x: 52, y: 52), type: .leftMouseDragged)
        XCTAssertFalse(FloatingLyricsController.shouldStartDrag(
            beginEvent: begin, currentEvent: drag, thresholdPoints: 4))
    }
}
