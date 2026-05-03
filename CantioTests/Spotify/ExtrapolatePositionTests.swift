import XCTest
@testable import Cantio

final class ExtrapolatePositionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func test_extrapolate_nilAnchor_returnsNil() {
        let result = extrapolatePosition(anchor: nil, now: t0)

        XCTAssertNil(result)
    }

    func test_extrapolate_pausedAnchor_returnsAnchorPositionRegardlessOfNow() {
        let anchor = PositionAnchor(position: 30.0, sampledAt: t0, isPlaying: false)

        let result = extrapolatePosition(anchor: anchor, now: t0.addingTimeInterval(120))

        XCTAssertEqual(result, 30.0)
    }

    func test_extrapolate_playingAnchorAtSampledInstant_returnsAnchorPosition() {
        let anchor = PositionAnchor(position: 12.5, sampledAt: t0, isPlaying: true)

        let result = extrapolatePosition(anchor: anchor, now: t0)

        XCTAssertEqual(result, 12.5)
    }

    func test_extrapolate_playingAnchorFiveSecondsLater_advancesByFive() {
        let anchor = PositionAnchor(position: 10.0, sampledAt: t0, isPlaying: true)

        let result = extrapolatePosition(anchor: anchor, now: t0.addingTimeInterval(5))

        XCTAssertEqual(result ?? 0, 15.0, accuracy: 0.0001)
    }

    func test_extrapolate_playingAnchorWithClockSkewBeforeSampledAt_clampsToAnchorPosition() {
        let anchor = PositionAnchor(position: 50.0, sampledAt: t0, isPlaying: true)

        let result = extrapolatePosition(anchor: anchor, now: t0.addingTimeInterval(-3))

        XCTAssertEqual(result, 50.0)
    }
}
