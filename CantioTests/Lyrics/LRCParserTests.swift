import XCTest
@testable import Cantio

final class LRCParserTests: XCTestCase {
    func test_parse_emptyInput_returnsEmpty() {
        let result = LRCParser.parse("")

        XCTAssertEqual(result, [])
    }

    func test_parse_basicMMSS_returnsLineWithSeconds() {
        let result = LRCParser.parse("[01:02]hello")

        XCTAssertEqual(result, [LyricLine(timestamp: 62, text: "hello")])
    }

    func test_parse_mmssWithFraction_returnsFractionalSeconds() {
        let result = LRCParser.parse("[00:10.50]half")

        XCTAssertEqual(result, [LyricLine(timestamp: 10.5, text: "half")])
    }

    func test_parse_mmssWithMillisecondFraction_returnsFractionalSeconds() {
        let result = LRCParser.parse("[00:01.250]ms")

        XCTAssertEqual(result, [LyricLine(timestamp: 1.25, text: "ms")])
    }

    func test_parse_multipleStampsOnSingleLine_emitsLinePerStamp() {
        let result = LRCParser.parse("[00:10.00][00:20.00]chorus")

        XCTAssertEqual(result, [
            LyricLine(timestamp: 10, text: "chorus"),
            LyricLine(timestamp: 20, text: "chorus"),
        ])
    }

    func test_parse_metadataTag_isSkipped() {
        let result = LRCParser.parse("[ar:Foo]\n[00:05.00]line")

        XCTAssertEqual(result, [LyricLine(timestamp: 5, text: "line")])
    }

    func test_parse_unsortedInput_returnsSortedByTimestamp() {
        let src = "[00:30.00]c\n[00:10.00]a\n[00:20.00]b"

        let result = LRCParser.parse(src)

        XCTAssertEqual(result.map(\.timestamp), [10, 20, 30])
    }

    func test_parse_multipleLines_preservesEachLineText() {
        let src = "[00:01.00]first\n[00:02.00]second"

        let result = LRCParser.parse(src)

        XCTAssertEqual(result, [
            LyricLine(timestamp: 1, text: "first"),
            LyricLine(timestamp: 2, text: "second"),
        ])
    }

    func test_parse_malformedLineNoTimestamp_isDropped() {
        let src = "no brackets here\n[00:01.00]kept"

        let result = LRCParser.parse(src)

        XCTAssertEqual(result, [LyricLine(timestamp: 1, text: "kept")])
    }

    func test_parse_emptyLyricText_returnsEmptyTextLine() {
        let result = LRCParser.parse("[00:05.00]")

        XCTAssertEqual(result, [LyricLine(timestamp: 5, text: "")])
    }
}
