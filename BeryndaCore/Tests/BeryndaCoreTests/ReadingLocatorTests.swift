import Foundation
import XCTest
@testable import BeryndaCore

final class ReadingLocatorTests: XCTestCase {
    func testEncodesTheKeysTheAPIStores() throws {
        let locator = ReadingLocator(
            href: "OEBPS/ch01.xhtml",
            progression: 0.5,
            totalProgression: 0.25,
            cfi: "epubcfi(/6/4!/4/2)"
        )
        let encoded = try XCTUnwrap(locator.encoded())
        let decoded = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any]
        )

        XCTAssertEqual(decoded["href"] as? String, "OEBPS/ch01.xhtml")
        XCTAssertEqual(decoded["progression"] as? Double, 0.5)
        // snake_case, matching the API rather than Swift's spelling.
        XCTAssertEqual(decoded["total_progression"] as? Double, 0.25)
        XCTAssertEqual(decoded["cfi"] as? String, "epubcfi(/6/4!/4/2)")
    }

    func testAbsentFieldsAreOmittedRatherThanSentAsNull() throws {
        let encoded = try XCTUnwrap(ReadingLocator(totalProgression: 0.1).encoded())
        XCTAssertFalse(encoded.contains("href"))
        XCTAssertFalse(encoded.contains("null"))
    }

    func testRoundTripsThroughTheStoredRepresentation() throws {
        let original = ReadingLocator(href: "ch01.xhtml", progression: 0.5, totalProgression: 0.2)
        let restored = try XCTUnwrap(ReadingLocator.decode(from: try XCTUnwrap(original.encoded())))
        XCTAssertEqual(restored, original)
    }

    func testPreservesACFIItCannotItselfResolve() throws {
        // A CFI written by the web reader has to survive a round trip through
        // this client, or opening a book on a phone would strip the web
        // reader's own way of restoring exactly.
        let fromWeb = try XCTUnwrap(
            ReadingLocator.decode(from: #"{"href":"ch01.xhtml","cfi":"epubcfi(/6/4!/4/2)"}"#)
        )
        XCTAssertEqual(fromWeb.cfi, "epubcfi(/6/4!/4/2)")
        XCTAssertTrue(try XCTUnwrap(fromWeb.encoded()).contains("epubcfi"))
    }

    func testRestorabilityMatchesWhatTheAPIAccepts() {
        XCTAssertTrue(ReadingLocator(href: "ch01.xhtml").isRestorable)
        XCTAssertTrue(ReadingLocator(totalProgression: 0.3).isRestorable)
        // Progress within an unnamed resource locates nothing, and a CFI alone
        // is unreadable by a client without a CFI implementation — which is the
        // problem this type exists to solve.
        XCTAssertFalse(ReadingLocator(progression: 0.5).isRestorable)
        XCTAssertFalse(ReadingLocator(cfi: "epubcfi(/6/4)").isRestorable)
        XCTAssertFalse(ReadingLocator().isRestorable)
    }

    func testMalformedStoredValuesDecodeToNothing() {
        XCTAssertNil(ReadingLocator.decode(from: ""))
        XCTAssertNil(ReadingLocator.decode(from: "not json"))
        XCTAssertNil(ReadingLocator.decode(from: "[]"))
    }

    func testOnlyALocatorPositionYieldsALocator() throws {
        let locatorPosition = try position(type: "locator", value: #"{"href":"ch01.xhtml"}"#)
        XCTAssertEqual(locatorPosition.locator?.href, "ch01.xhtml")

        // A page or CFI position is not a locator and must not be read as one.
        XCTAssertNil(try position(type: "page", value: "12").locator)
        XCTAssertNil(try position(type: "epub_cfi", value: "epubcfi(/6/4)").locator)
    }

    private func position(type: String, value: String) throws -> ReadingPosition {
        let json = """
        {
          "position_type": "\(type)",
          "position_value": \(try encodeJSONString(value)),
          "progress_percent": null,
          "total_pages": null,
          "last_read_at": null
        }
        """
        return try JSONDecoder().decode(ReadingPosition.self, from: Data(json.utf8))
    }

    private func encodeJSONString(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value])
        let array = try XCTUnwrap(String(data: data, encoding: .utf8))
        return String(array.dropFirst().dropLast())
    }
}
