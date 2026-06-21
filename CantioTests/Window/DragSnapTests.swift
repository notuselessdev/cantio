import XCTest
import AppKit
@testable import Cantio

final class DragSnapTests: XCTestCase {
    private let size = NSSize(width: 520, height: 80)
    // A simple full-HD-ish visible frame anchored away from origin to catch
    // any code that assumes minX/minY == 0.
    private let visible = NSRect(x: 100, y: 50, width: 1440, height: 850)

    // MARK: - defaultOrigin

    func test_defaultOrigin_isHorizontallyCentered() {
        let o = DragSnap.defaultOrigin(in: visible, size: size)
        XCTAssertEqual(o.x + size.width / 2, visible.midX, accuracy: 0.001)
    }

    func test_defaultOrigin_anchorsBottomInsetAboveVisibleBottom() {
        let o = DragSnap.defaultOrigin(in: visible, size: size)
        XCTAssertEqual(o.y, visible.minY + DragSnap.bottomInset, accuracy: 0.001)
    }

    // MARK: - snap: horizontal center

    func test_snap_centerWithinThreshold_snapsX() {
        let def = DragSnap.defaultOrigin(in: visible, size: size)
        // Window center 5pt right of screen center — within 8pt threshold.
        let proposed = NSPoint(x: visible.midX - size.width / 2 + 5, y: 200)
        let r = DragSnap.snap(proposedOrigin: proposed, windowSize: size,
                              visibleFrame: visible, defaultOrigin: def)
        XCTAssertTrue(r.snapX)
        XCTAssertEqual(r.origin.x + size.width / 2, visible.midX, accuracy: 0.001)
    }

    func test_snap_centerOutsideThreshold_doesNotSnapX() {
        let def = DragSnap.defaultOrigin(in: visible, size: size)
        let proposed = NSPoint(x: visible.midX - size.width / 2 + 40, y: 200)
        let r = DragSnap.snap(proposedOrigin: proposed, windowSize: size,
                              visibleFrame: visible, defaultOrigin: def)
        XCTAssertFalse(r.snapX)
        XCTAssertEqual(r.origin.x, proposed.x, accuracy: 0.001)
    }

    // MARK: - snap: vertical baseline

    func test_snap_baselineWithinThreshold_snapsY() {
        let def = DragSnap.defaultOrigin(in: visible, size: size)
        let proposed = NSPoint(x: 600, y: def.y - 6)
        let r = DragSnap.snap(proposedOrigin: proposed, windowSize: size,
                              visibleFrame: visible, defaultOrigin: def)
        XCTAssertTrue(r.snapY)
        XCTAssertEqual(r.origin.y, def.y, accuracy: 0.001)
    }

    func test_snap_baselineOutsideThreshold_doesNotSnapY() {
        let def = DragSnap.defaultOrigin(in: visible, size: size)
        let proposed = NSPoint(x: 600, y: def.y + 50)
        let r = DragSnap.snap(proposedOrigin: proposed, windowSize: size,
                              visibleFrame: visible, defaultOrigin: def)
        XCTAssertFalse(r.snapY)
        XCTAssertEqual(r.origin.y, proposed.y, accuracy: 0.001)
    }

    // MARK: - axes are independent

    func test_snap_axesIndependent_xSnapsYDoesNot() {
        let def = DragSnap.defaultOrigin(in: visible, size: size)
        let proposed = NSPoint(x: visible.midX - size.width / 2 + 3, y: def.y + 200)
        let r = DragSnap.snap(proposedOrigin: proposed, windowSize: size,
                              visibleFrame: visible, defaultOrigin: def)
        XCTAssertTrue(r.snapX)
        XCTAssertFalse(r.snapY)
        XCTAssertEqual(r.origin.y, proposed.y, accuracy: 0.001)
    }
}
