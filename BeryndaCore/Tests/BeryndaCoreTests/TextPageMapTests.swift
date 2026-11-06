import XCTest
@testable import BeryndaCore

final class TextPageMapTests: XCTestCase {
    func testOffsetsMapToTheirPages() {
        let map = TextPageMap(pageStarts: [0, 10, 25, 40], textLength: 50)

        XCTAssertEqual(map.pageCount, 4)
        XCTAssertEqual(map.page(containing: 0), 1)
        XCTAssertEqual(map.page(containing: 9), 1)
        XCTAssertEqual(map.page(containing: 10), 2)
        XCTAssertEqual(map.page(containing: 24), 2)
        XCTAssertEqual(map.page(containing: 25), 3)
        XCTAssertEqual(map.page(containing: 49), 4)
        XCTAssertEqual(map.page(containing: 50), 4)
    }

    func testEveryPageStartRoundTrips() {
        let map = TextPageMap(pageStarts: [0, 7, 19, 33, 34, 80], textLength: 100)
        for page in 1...map.pageCount {
            XCTAssertEqual(map.page(containing: map.startOffset(ofPage: page)), page)
        }
    }

    func testOutOfRangeOffsetsAndPagesAreClamped() {
        let map = TextPageMap(pageStarts: [0, 10, 20], textLength: 30)

        XCTAssertEqual(map.page(containing: -5), 1)
        XCTAssertEqual(map.page(containing: 10_000), 3)
        XCTAssertEqual(map.startOffset(ofPage: 0), 0)
        XCTAssertEqual(map.startOffset(ofPage: 99), 20)
        XCTAssertEqual(map.endOffset(ofPage: 1), 10)
        XCTAssertEqual(map.endOffset(ofPage: 3), 30)
        XCTAssertEqual(map.endOffset(ofPage: 99), 30)
    }

    func testUntrustedStartsAreSanitisedWithoutChangingThePageCount() {
        let map = TextPageMap(pageStarts: [4, 12, 8, -3, 500], textLength: 40)

        XCTAssertEqual(map.pageStarts, [0, 12, 12, 12, 40])
        XCTAssertEqual(map.pageCount, 5)
    }

    func testEmptyInputStillHasOnePage() {
        let map = TextPageMap(pageStarts: [], textLength: 0)

        XCTAssertEqual(map.pageCount, 1)
        XCTAssertEqual(map.page(containing: 12), 1)
        XCTAssertEqual(map.progressPercent(at: 0), 0)
    }

    func testProgressIsOffsetOverLength() {
        let map = TextPageMap(pageStarts: [0, 50], textLength: 200)

        XCTAssertEqual(map.progressPercent(at: 0), 0)
        XCTAssertEqual(map.progressPercent(at: 50), 25)
        XCTAssertEqual(map.progressPercent(at: 199), 100)
        XCTAssertEqual(map.progressPercent(at: 999), 100)
    }

    /// Offsets are UTF-16 code units — what the web reader stores — not
    /// Swift characters or Unicode scalars.
    func testOffsetsAreCountedInUTF16() {
        // 👍🏽 is one Character, two scalars and four UTF-16 units; CRLF is one
        // Character and two units; a decomposed «й» is one Character and two
        // units.
        let body = "👍🏽\r\nи\u{0306}x"
        XCTAssertEqual(body.count, 4)
        XCTAssertEqual(body.utf16.count, 9)

        let xIndex = body.firstIndex(of: "x")!
        XCTAssertEqual(body.utf16Offset(of: xIndex), 8)

        let map = TextPageMap(pageStarts: [0, 4, 6], textLength: body.utf16.count)
        XCTAssertEqual(map.page(containing: body.utf16Offset(of: xIndex)), 3)
        let crlfIndex = body.firstIndex(of: "\r\n")!
        XCTAssertEqual(map.page(containing: body.utf16Offset(of: crlfIndex)), 2)
    }

    func testIdentitySourceMapIsExact() {
        let body = "Тіні 👍🏽 забутих\r\nпредків"
        let map = TextSourceMap.identity(length: body.utf16.count)

        for offset in [0, 5, 9, 17, body.utf16.count] {
            XCTAssertEqual(map.sourceOffset(forRendered: offset), offset)
        }
        XCTAssertEqual(map.sourceOffset(forRendered: 10_000), body.utf16.count)
    }

    func testMarkdownBlocksMapRenderedOffsetsBackToTheSource() {
        let blocks: [(source: String, rendered: String)] = [
            (source: "Перший рядок\r\n", rendered: "Перший рядок\r\n"),
            (source: "**Жирний** 👍🏽\n", rendered: "Жирний 👍🏽\n"),
            (source: "Кінець", rendered: "Кінець"),
        ]
        let map = TextSourceMap(blocks: blocks)
        let first = blocks[0].source.utf16.count
        let second = blocks[1].source.utf16.count
        let renderedSecond = blocks[1].rendered.utf16.count

        XCTAssertEqual(map.sourceLength, blocks.map { $0.source.utf16.count }.reduce(0, +))
        XCTAssertEqual(map.renderedLength, blocks.map { $0.rendered.utf16.count }.reduce(0, +))
        // An unchanged block maps exactly.
        XCTAssertEqual(map.sourceOffset(forRendered: 3), 3)
        // A block start maps to the source block start.
        XCTAssertEqual(map.sourceOffset(forRendered: first), first)
        XCTAssertEqual(map.sourceOffset(forRendered: first + renderedSecond), first + second)
        // Inside a block that lost markup the mapping stays inside the block.
        let inside = map.sourceOffset(forRendered: first + 3)
        XCTAssertGreaterThanOrEqual(inside, first)
        XCTAssertLessThan(inside, first + second)
        // And it never runs backwards.
        var previous = 0
        for offset in 0...map.renderedLength {
            let mapped = map.sourceOffset(forRendered: offset)
            XCTAssertGreaterThanOrEqual(mapped, previous)
            previous = mapped
        }
    }

    func testABlockThatRendersToNothingIsSkipped() {
        let map = TextSourceMap(blocks: [
            (source: "Аб", rendered: "Аб"),
            (source: "****", rendered: ""),
            (source: "Вг", rendered: "Вг"),
        ])

        XCTAssertEqual(map.sourceOffset(forRendered: 2), 6)
        XCTAssertEqual(map.sourceOffset(forRendered: 3), 7)
    }
}
