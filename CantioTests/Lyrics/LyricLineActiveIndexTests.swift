import XCTest
@testable import Cantio

final class LyricLineActiveIndexTests: XCTestCase {
    private let sample: [LyricLine] = [
        LyricLine(timestamp: 1, text: "a"),
        LyricLine(timestamp: 5, text: "b"),
        LyricLine(timestamp: 9, text: "c"),
    ]

    func test_activeIndex_emptyLines_returnsNil() {
        let result = LyricLine.activeIndex(in: [], at: 10)

        XCTAssertNil(result)
    }

    func test_activeIndex_singleLineBeforeStamp_returnsNil() {
        let lines = [LyricLine(timestamp: 5, text: "only")]

        let result = LyricLine.activeIndex(in: lines, at: 1)

        XCTAssertNil(result)
    }

    func test_activeIndex_singleLineAtOrAfterStamp_returnsZero() {
        let lines = [LyricLine(timestamp: 5, text: "only")]

        let result = LyricLine.activeIndex(in: lines, at: 5)

        XCTAssertEqual(result, 0)
    }

    func test_activeIndex_positionBeforeFirst_returnsNil() {
        let result = LyricLine.activeIndex(in: sample, at: 0)

        XCTAssertNil(result)
    }

    func test_activeIndex_positionExactlyOnStamp_returnsThatIndex() {
        let result = LyricLine.activeIndex(in: sample, at: 5)

        XCTAssertEqual(result, 1)
    }

    func test_activeIndex_positionBetweenStamps_returnsLowerIndex() {
        let result = LyricLine.activeIndex(in: sample, at: 7)

        XCTAssertEqual(result, 1)
    }

    func test_activeIndex_positionPastLast_returnsLastIndex() {
        let result = LyricLine.activeIndex(in: sample, at: 999)

        XCTAssertEqual(result, 2)
    }
}
