import XCTest
import AppKit
@testable import Cantio

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

    // MARK: - Capsule shape hit-test

    /// Window at screen origin (100, 200) sized 520x80. Capsule sits centered
    /// horizontally (SwiftUI top-left coords): x in [160, 360], y in [20, 60]
    /// → height 40, width 200. After Y-flip against window height (80):
    /// AppKit screen y in [windowMinY + (80 - 60), windowMinY + (80 - 20)]
    ///                  = [200 + 20, 200 + 60] = [220, 260].
    /// AppKit screen x in [100 + 160, 100 + 360] = [260, 460].
    private let testWindowFrame = NSRect(x: 100, y: 200, width: 520, height: 80)
    private let testCapsuleRect = CGRect(x: 160, y: 20, width: 200, height: 40)

    func test_pointInsideCapsuleRect_centerInside_returnsTrue() {
        // Center: (360, 240) in screen coords.
        XCTAssertTrue(FloatingLyricsController.pointInsideCapsuleRect(
            mouseScreen: NSPoint(x: 360, y: 240),
            capsuleInContentView: testCapsuleRect,
            windowFrame: testWindowFrame))
    }

    func test_pointInsideCapsuleRect_outsideLeft_returnsFalse() {
        XCTAssertFalse(FloatingLyricsController.pointInsideCapsuleRect(
            mouseScreen: NSPoint(x: 200, y: 240),
            capsuleInContentView: testCapsuleRect,
            windowFrame: testWindowFrame))
    }

    func test_pointInsideCapsuleRect_outsideRight_returnsFalse() {
        XCTAssertFalse(FloatingLyricsController.pointInsideCapsuleRect(
            mouseScreen: NSPoint(x: 500, y: 240),
            capsuleInContentView: testCapsuleRect,
            windowFrame: testWindowFrame))
    }

    func test_pointInsideCapsuleRect_outsideAbove_returnsFalse() {
        // SwiftUI top of capsule (y=20) maps to screen y=260; above = y > 260.
        XCTAssertFalse(FloatingLyricsController.pointInsideCapsuleRect(
            mouseScreen: NSPoint(x: 360, y: 270),
            capsuleInContentView: testCapsuleRect,
            windowFrame: testWindowFrame))
    }

    func test_pointInsideCapsuleRect_outsideBelow_returnsFalse() {
        // SwiftUI bottom of capsule (y=60) maps to screen y=220; below = y < 220.
        XCTAssertFalse(FloatingLyricsController.pointInsideCapsuleRect(
            mouseScreen: NSPoint(x: 360, y: 210),
            capsuleInContentView: testCapsuleRect,
            windowFrame: testWindowFrame))
    }

    func test_pointInsideCapsuleRect_zeroRect_returnsFalse() {
        // No capsule reported yet — must not falsely claim hits.
        XCTAssertFalse(FloatingLyricsController.pointInsideCapsuleRect(
            mouseScreen: NSPoint(x: 360, y: 240),
            capsuleInContentView: .zero,
            windowFrame: testWindowFrame))
    }
}
