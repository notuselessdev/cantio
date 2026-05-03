import XCTest
@testable import Floric

final class FontSizeTests: XCTestCase {
    func test_allCases_count_isFive() {
        XCTAssertEqual(FontSize.allCases.count, 5)
    }

    func test_activeSize_monotonicallyIncreasingByRawValue() {
        let ordered = FontSize.allCases.sorted { $0.rawValue < $1.rawValue }
        let sizes = ordered.map { $0.activeSize }
        XCTAssertEqual(sizes, sizes.sorted())
        XCTAssertEqual(Set(sizes).count, sizes.count)
    }

    func test_bodySize_monotonicallyIncreasingByRawValue() {
        let ordered = FontSize.allCases.sorted { $0.rawValue < $1.rawValue }
        let sizes = ordered.map { $0.bodySize }
        XCTAssertEqual(sizes, sizes.sorted())
        XCTAssertEqual(Set(sizes).count, sizes.count)
    }

    func test_xsmall_rawValueNegativeOne_preservesLegacyMigration() {
        XCTAssertEqual(FontSize.xsmall.rawValue, -1)
        XCTAssertEqual(FontSize.small.rawValue, 0)
        XCTAssertEqual(FontSize.medium.rawValue, 1)
        XCTAssertEqual(FontSize.large.rawValue, 2)
        XCTAssertEqual(FontSize.xlarge.rawValue, 3)
    }
}
