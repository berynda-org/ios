import XCTest
@testable import BeryndaCore

final class ReaderNavigationTests: XCTestCase {
    private let workID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    func testContentsFlattensNestedEntriesAndPreservesDepth() {
        let child = entry(title: "  Розділ 1  ", page: 3)
        let root = entry(title: "Частина I", page: 1, children: [child])

        let items = ReaderNavigation.contents(from: [root], workID: workID, totalPages: 10)

        XCTAssertEqual(items.map(\.title), ["Частина I", "Розділ 1"])
        XCTAssertEqual(items.map(\.page), [1, 3])
        XCTAssertEqual(items.map(\.depth), [0, 1])
    }

    func testContentsRejectsInvalidAndCrossWorkDestinations() {
        let anotherWork = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let entries = [
            entry(title: "Без сторінки", page: nil),
            entry(title: "Нуль", page: 0),
            entry(title: "За межами", page: 11),
            entry(title: "Інший твір", page: 2, workID: anotherWork),
            entry(title: "Дійсний", page: 4),
        ]

        let items = ReaderNavigation.contents(from: entries, workID: workID, totalPages: 10)

        XCTAssertEqual(items.map(\.title), ["Дійсний"])
        XCTAssertEqual(items.map(\.page), [4])
    }

    func testPageLabelTrimsContentAndIgnoresEmptyLabels() {
        let labels = [
            ReaderPageLabel(page: 1, label: "  Обкладинка  ", source: "manual"),
            ReaderPageLabel(page: 2, label: "   ", source: "manual"),
        ]

        XCTAssertEqual(ReaderNavigation.pageLabel(for: 1, in: labels), "Обкладинка")
        XCTAssertNil(ReaderNavigation.pageLabel(for: 2, in: labels))
        XCTAssertNil(ReaderNavigation.pageLabel(for: 3, in: labels))
    }

    private func entry(
        title: String,
        page: Int?,
        workID: UUID? = nil,
        children: [ReaderTOCEntry] = []
    ) -> ReaderTOCEntry {
        ReaderTOCEntry(
            id: UUID(),
            ordinal: 0,
            title: title,
            pageNumber: page,
            anchor: nil,
            level: 0,
            workID: workID,
            children: children
        )
    }
}
