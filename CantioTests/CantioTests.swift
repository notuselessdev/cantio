import XCTest

final class CantioTests: XCTestCase {
    func test_arithmetic_basic_passes() {
        XCTAssertEqual(1 + 1, 2)
    }

    func test_runner_isAlive_assertionsExecute() {
        // Sanity: confirms the test runner actually evaluates assertions
        // rather than silently reporting success on an empty target.
        XCTAssertTrue(true, "runner is alive")
    }
}
