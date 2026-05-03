import XCTest
@testable import Floric

final class LyricPositionTests: XCTestCase {
    private let sample: [LyricLine] = [
        LyricLine(timestamp: 1, text: "alpha"),
        LyricLine(timestamp: 5, text: "bravo charlie"),
        LyricLine(timestamp: 9, text: ""),
    ]

    func test_compute_emptyLines_returnsAllNil() {
        let lp = LyricPosition.compute(lines: [], position: 5)

        XCTAssertNil(lp.prev)
        XCTAssertNil(lp.current)
        XCTAssertNil(lp.next)
    }

    func test_compute_positionBeforeFirst_currentNilNextIsFirst() {
        let lp = LyricPosition.compute(lines: sample, position: 0)

        XCTAssertNil(lp.prev)
        XCTAssertNil(lp.current)
        XCTAssertEqual(lp.next?.timestamp, 1)
    }

    func test_compute_positionAtFirst_prevNilCurrentFirst() {
        let lp = LyricPosition.compute(lines: sample, position: 1)

        XCTAssertNil(lp.prev)
        XCTAssertEqual(lp.current?.timestamp, 1)
        XCTAssertEqual(lp.next?.timestamp, 5)
    }

    func test_compute_positionInMiddle_returnsPrevCurrentNext() {
        let lp = LyricPosition.compute(lines: sample, position: 6)

        XCTAssertEqual(lp.prev?.timestamp, 1)
        XCTAssertEqual(lp.current?.timestamp, 5)
        XCTAssertEqual(lp.next?.timestamp, 9)
    }

    func test_compute_positionAtLast_nextIsNil() {
        let lp = LyricPosition.compute(lines: sample, position: 9)

        XCTAssertEqual(lp.prev?.timestamp, 5)
        XCTAssertEqual(lp.current?.timestamp, 9)
        XCTAssertNil(lp.next)
    }

    func test_compute_emptyTextLine_fallsBackToMusicNote() {
        let lp = LyricPosition.compute(lines: sample, position: 9)

        XCTAssertEqual(lp.current?.text, "♪")
        XCTAssertEqual(lp.current?.words, ["♪"])
    }

    func test_compute_multiWordLine_splitsIntoWords() {
        let lp = LyricPosition.compute(lines: sample, position: 5)

        XCTAssertEqual(lp.current?.words, ["bravo", "charlie"])
    }

    func test_compute_singleLineInputBeforeStamp_currentNilNextIsLine() {
        let single = [LyricLine(timestamp: 10, text: "only")]

        let lp = LyricPosition.compute(lines: single, position: 0)

        XCTAssertNil(lp.current)
        XCTAssertEqual(lp.next?.timestamp, 10)
    }
}
