import BeryndaCore
import Foundation
import XCTest
@testable import Berynda

final class LocalStorageSummaryTests: XCTestCase {
    func testEmptyDirectoriesReportZeroEverywhere() async {
        let fixture = makeFixture()

        let usage = await fixture.summary.measure()

        XCTAssertEqual(usage, .empty)
        XCTAssertEqual(usage.readingPositionsBytes, 0)
        XCTAssertEqual(usage.recentlyViewedBytes, 0)
        XCTAssertEqual(usage.readerTemporaryBytes, 0)
        XCTAssertEqual(usage.totalBytes, 0)
    }

    func testStoredPositionAndHistoryAreCountedAndSummed() async throws {
        let fixture = makeFixture()
        let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

        await fixture.readingPositions.save(page: 7, totalPages: 20, for: fileID)
        await fixture.recentlyViewed.record(try Self.recentWork())

        let usage = await fixture.summary.measure()

        XCTAssertGreaterThan(usage.readingPositionsBytes, 0)
        XCTAssertGreaterThan(usage.recentlyViewedBytes, 0)
        XCTAssertEqual(usage.readerTemporaryBytes, 0)
        XCTAssertEqual(
            usage.totalBytes,
            usage.readingPositionsBytes + usage.recentlyViewedBytes + usage.readerTemporaryBytes
        )
    }

    func testClearingRemovesStrayReaderFilesAndEmptiesBothStores() async throws {
        let fixture = makeFixture()
        let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        await fixture.readingPositions.save(page: 3, totalPages: nil, for: fileID)
        await fixture.recentlyViewed.record(try Self.recentWork())

        // A copy the reader would have deleted on close, had it not crashed.
        try FileManager.default.createDirectory(
            at: fixture.readerTemporaryDirectory,
            withIntermediateDirectories: true
        )
        let stray = fixture.readerTemporaryDirectory.appendingPathComponent("leftover.pdf")
        let strayBytes = Data(repeating: 0x41, count: 4_096)
        try strayBytes.write(to: stray)

        let before = await fixture.summary.measure()
        XCTAssertEqual(before.readerTemporaryBytes, Int64(strayBytes.count))

        let after = await fixture.summary.clearCaches()

        XCTAssertEqual(after, .empty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stray.path))
        let position = await fixture.readingPositions.position(for: fileID)
        XCTAssertNil(position)
        let recent = await fixture.recentlyViewed.recent()
        XCTAssertTrue(recent.isEmpty)
    }

    // MARK: - Fixtures

    private struct Fixture {
        let readingPositions: LocalReadingPositionStore
        let recentlyViewed: RecentlyViewedStore
        let readerTemporaryDirectory: URL
        let summary: LocalStorageSummary
    }

    /// Both stores share one support directory, as they do in the app; the
    /// reader directory is deliberately not created so a missing directory is
    /// exercised as "zero", not as a failure.
    private func makeFixture() -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeryndaTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("support", isDirectory: true)
        let readerTemporary = root.appendingPathComponent("reader", isDirectory: true)
        let readingPositions = LocalReadingPositionStore(directory: support)
        let recentlyViewed = RecentlyViewedStore(directory: support)
        return Fixture(
            readingPositions: readingPositions,
            recentlyViewed: recentlyViewed,
            readerTemporaryDirectory: readerTemporary,
            summary: LocalStorageSummary(
                readingPositions: readingPositions,
                recentlyViewed: recentlyViewed,
                readerTemporaryDirectory: readerTemporary
            )
        )
    }

    /// The same list-row shape `BeryndaTests.listRow()` decodes; `WorkSummary`
    /// has no public memberwise initializer.
    private static func recentWork() throws -> WorkSummary {
        let json = """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "slug": "lisova-pisnia",
          "title": "Лісова пісня",
          "subtitle": null,
          "language": "uk",
          "first_published_year": 1912,
          "authors": [{"id": "88888888-8888-8888-8888-888888888888", "display_name": "Леся Українка"}],
          "editions_count": 1,
          "has_text_file": true,
          "cover_image_url": null,
          "cover_tone": null,
          "cover_variant": null,
          "cover_glyph": null
        }
        """
        return try JSONDecoder().decode(WorkSummary.self, from: Data(json.utf8))
    }
}
