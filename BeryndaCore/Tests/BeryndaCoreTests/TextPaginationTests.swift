import Foundation
import XCTest
@testable import BeryndaCore

final class TextPaginationTests: XCTestCase {
    func testSplitsCyrillicTextOnScalarOffsets() {
        // "Еней" is four Cyrillic characters — two UTF-16 units each and two
        // bytes each in UTF-8 — so an implementation counting either would cut
        // in the wrong place.
        let text = "Еней був"
        let ranges = TextPagination.pageRanges(in: text, offsets: [0, 4])

        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(TextPagination.page(1, in: text, ranges: ranges), "Еней")
        XCTAssertEqual(TextPagination.page(2, in: text, ranges: ranges), " був")
    }

    func testOffsetsAreScalarsNotBytes() {
        let text = "абв"
        let ranges = TextPagination.pageRanges(in: text, offsets: [0, 1, 2])

        XCTAssertEqual(TextPagination.page(1, in: text, ranges: ranges), "а")
        XCTAssertEqual(TextPagination.page(2, in: text, ranges: ranges), "б")
        XCTAssertEqual(TextPagination.page(3, in: text, ranges: ranges), "в")
    }

    func testUnpaginatedBodyYieldsNoRangesAndReadsWhole() {
        let text = "Суцільний текст"
        let ranges = TextPagination.pageRanges(in: text, offsets: [])

        XCTAssertTrue(ranges.isEmpty)
        XCTAssertEqual(TextPagination.page(1, in: text, ranges: ranges), text)
    }

    func testPageNumbersAreClampedToTheDocument() {
        let text = "Один два три"
        let ranges = TextPagination.pageRanges(in: text, offsets: [0, 5])

        XCTAssertEqual(TextPagination.page(0, in: text, ranges: ranges), "Один ")
        XCTAssertEqual(TextPagination.page(-3, in: text, ranges: ranges), "Один ")
        XCTAssertEqual(TextPagination.page(99, in: text, ranges: ranges), "два три")
    }

    func testEveryPageConcatenatesBackToTheWholeBody() {
        let text = "Сторінка перша. Сторінка друга. Сторінка третя."
        let ranges = TextPagination.pageRanges(in: text, offsets: [0, 16, 32])

        let rebuilt = (1...ranges.count)
            .map { TextPagination.page($0, in: text, ranges: ranges) }
            .joined()
        XCTAssertEqual(rebuilt, text)
    }

    func testMalformedOffsetsAreRepairedRatherThanTrusted() {
        let scalarCount = "абвгд".unicodeScalars.count

        // Out of order, duplicated, negative, and past the end.
        XCTAssertEqual(
            TextPagination.sanitise([0, 3, 1, 3, -5, 99], scalarCount: scalarCount),
            [0, 3, 5]
        )
        // A body whose first offset is not zero would lose its opening.
        XCTAssertEqual(TextPagination.sanitise([2, 4], scalarCount: scalarCount), [0, 2, 4])
    }

    func testOffsetsPastTheEndStillProduceUsableRanges() {
        let text = "Коротко"
        let ranges = TextPagination.pageRanges(in: text, offsets: [0, 4, 900])

        XCTAssertEqual(ranges.count, 3)
        XCTAssertEqual(TextPagination.page(1, in: text, ranges: ranges), "Коро")
        XCTAssertEqual(TextPagination.page(2, in: text, ranges: ranges), "тко")
        XCTAssertEqual(TextPagination.page(3, in: text, ranges: ranges), "")
    }

    func testCombiningMarksDoNotShiftLaterPages() {
        // "й" written as и + combining breve is two scalars but one Character.
        let text = "и\u{0306}ой"
        let ranges = TextPagination.pageRanges(in: text, offsets: [0, 2])

        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(TextPagination.page(2, in: text, ranges: ranges), "ой")
    }
}
