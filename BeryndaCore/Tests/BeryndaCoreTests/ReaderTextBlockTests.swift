import XCTest
@testable import BeryndaCore

final class ReaderTextBlockTests: XCTestCase {
    func testLongCRLFBookIsBoundedWithoutLosingContent() {
        let source = String(repeating: "Тіні забутих предків. " + String(repeating: "текст ", count: 24) + "\r\n", count: 625)
        let blocks = ReaderTextBlock.split(source)
        XCTAssertGreaterThan(blocks.count, 50)
        XCTAssertEqual(blocks.map(\.text).joined(), source)
        XCTAssertTrue(blocks.allSatisfy { $0.text.count <= 2_048 })
        var offset = 0
        for block in blocks {
            XCTAssertEqual(block.id, offset)
            offset += block.text.utf16.count
        }
    }

    func testSingleLineAndEmojiNeverProduceAnUnboundedOrBrokenBlock() {
        let source = String(repeating: "ї👩🏽‍💻", count: 10_000)
        let blocks = ReaderTextBlock.split(source, maximumCharacters: 127)
        XCTAssertEqual(blocks.map(\.text).joined(), source)
        XCTAssertTrue(blocks.allSatisfy { !$0.text.isEmpty && $0.text.count <= 127 })
        XCTAssertEqual(ReaderTextBlock.split(""), [])
    }
}
