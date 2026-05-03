import XCTest
import SwiftUI
import AppKit
@testable import Floric

/// FlowLayout is a SwiftUI `Layout`. Driving it through the `Layout` protocol
/// directly requires synthesizing `Layout.Subviews`, which has no public
/// initializer. Instead we host it inside an `NSHostingView`, give it a
/// fixed-width container, and read back the resulting frames.
final class FlowLayoutTests: XCTestCase {
    private let words = ["one", "two", "three", "four", "five"]
    private let wordSize = CGSize(width: 60, height: 20)
    private let spacing: CGFloat = 6

    /// Renders `FlowLayout` with N fixed-size word boxes at a given container
    /// width and returns the boxes' frames in container coordinates.
    @MainActor
    private func frames(forWidth width: CGFloat) -> [CGRect] {
        let host = NSHostingView(rootView: FlowLayoutHarness(
            count: words.count,
            wordSize: wordSize,
            spacing: spacing
        ))
        host.frame = CGRect(x: 0, y: 0, width: width, height: 600)
        host.layoutSubtreeIfNeeded()

        var found: [TaggedNSView] = []
        collectTagged(host, into: &found)
        // Sort by tag (insertion order).
        found.sort { $0.testTag < $1.testTag }
        return found.map { $0.convert($0.bounds, to: host) }
    }

    private func collectTagged(_ view: NSView, into out: inout [TaggedNSView]) {
        if let t = view as? TaggedNSView { out.append(t) }
        for sub in view.subviews { collectTagged(sub, into: &out) }
    }

    @MainActor
    func test_flowLayout_widthFitsAllWords_singleRow() {
        // 5 * 60 + 4 * 6 = 324
        let f = frames(forWidth: 400)

        XCTAssertEqual(f.count, 5)
        let ys = Set(f.map { Int($0.minY.rounded()) })
        XCTAssertEqual(ys.count, 1, "all words should share one Y row, got \(ys)")
    }

    @MainActor
    func test_flowLayout_narrowWidth_wrapsToTwoRows() {
        // Width fits ~3 words per row: 3 * 60 + 2 * 6 = 192. Use 200.
        let f = frames(forWidth: 200)

        XCTAssertEqual(f.count, 5)
        let ys = Set(f.map { Int($0.minY.rounded()) })
        XCTAssertEqual(ys.count, 2, "expected 2 rows, got Y=\(ys)")
    }

    @MainActor
    func test_flowLayout_veryNarrowWidth_wrapsToThreeRows() {
        // Width fits ~2 words per row: 2 * 60 + 6 = 126. Use 130.
        let f = frames(forWidth: 130)

        XCTAssertEqual(f.count, 5)
        let ys = Set(f.map { Int($0.minY.rounded()) })
        XCTAssertEqual(ys.count, 3, "expected 3 rows, got Y=\(ys)")
    }

    @MainActor
    func test_flowLayout_singleRow_centersWordsHorizontally() {
        let width: CGFloat = 400
        let f = frames(forWidth: width)
        let totalW = wordSize.width * CGFloat(words.count) + spacing * CGFloat(words.count - 1)
        let expectedLeading = (width - totalW) / 2

        // FlowLayout centers each row; the first word's minX should be ~expectedLeading.
        XCTAssertEqual(f[0].minX, expectedLeading, accuracy: 1.0,
                       "first word should be horizontally centered in row")
    }

    @MainActor
    func test_flowLayout_singleRow_spacingBetweenWords_isSpacingValue() {
        let f = frames(forWidth: 400)
        // Sort by minX in case rendering order differs.
        let sorted = f.sorted { $0.minX < $1.minX }
        let gap = sorted[1].minX - sorted[0].maxX

        XCTAssertEqual(gap, spacing, accuracy: 1.0)
    }
}

/// SwiftUI harness rendering N fixed-size colored boxes inside `FlowLayout`.
/// Each box wraps an `NSViewRepresentable` whose underlying NSView carries a
/// unique tag so the test can locate it.
private struct FlowLayoutHarness: View {
    let count: Int
    let wordSize: CGSize
    let spacing: CGFloat

    var body: some View {
        FlowLayout(spacing: spacing) {
            ForEach(0..<count, id: \.self) { i in
                TaggedBox(tag: 1000 + i)
                    .frame(width: wordSize.width, height: wordSize.height)
            }
        }
    }
}

final class TaggedNSView: NSView {
    var testTag: Int = 0
}

private struct TaggedBox: NSViewRepresentable {
    let tag: Int

    func makeNSView(context: Context) -> TaggedNSView {
        let v = TaggedNSView()
        v.testTag = tag
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.gray.cgColor
        return v
    }

    func updateNSView(_ nsView: TaggedNSView, context: Context) {
        nsView.testTag = tag
    }
}
