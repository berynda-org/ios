import Foundation
import XCTest
@testable import BeryndaCore

final class OfflineLibraryTests: XCTestCase {
    private let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    func testReaderInfoDecodesOfflineRightsAndOlderServersSayNo() throws {
        let info = try readerInfo(mode: "pdf", delivery: "client_full", offline: #"{"kind":"pages","total_pages":3,"max_age_days":30}"#)
        XCTAssertTrue(info.rights.canSaveOffline)
        XCTAssertEqual(info.offline, OfflinePolicy(kind: .pages, totalPages: 3, maxAgeDays: 30))

        let older = try fixtureInfo()
        XCTAssertFalse(older.rights.canSaveOffline)
        XCTAssertNil(older.offline)
    }

    func testAPagedCopyIsSavedAndReadFromStoredPages() async throws {
        let library = OfflineLibrary(directory: temporaryDirectory())
        let source = OfflineSourceStub(info: try readerInfo(
            mode: "pdf", delivery: "client_full",
            offline: #"{"kind":"pages","total_pages":3,"max_age_days":30}"#
        ))

        let copy = try await library.save(fileID: fileID, from: source)

        XCTAssertEqual(copy.kind, .pages)
        XCTAssertEqual(copy.totalPages, 3)
        let pages = await source.pageRequests
        XCTAssertEqual(pages, [1, 2, 3])
        let storedInfo = await library.readerInfo(fileID: fileID)
        let stored = try XCTUnwrap(storedInfo)
        XCTAssertEqual(stored.pageDelivery, .serverPages)
        XCTAssertEqual(stored.resource, .pageImage)
        let page = await library.pageImage(fileID: fileID, page: 2)
        XCTAssertEqual(page, Data("page-2".utf8))

        // Offline, the reader gets the saved record and pages.
        let reader = OfflineAwareReaderRepository(live: OfflineSourceStub(info: nil), library: library)
        let offlineInfo = try await reader.info(fileID: fileID)
        XCTAssertEqual(offlineInfo.resource, .pageImage)
        let offlinePage = try await reader.pageImage(fileID: fileID, page: 3, width: 1_600)
        XCTAssertEqual(offlinePage, Data("page-3".utf8))
    }

    func testTextIsSavedAsContent() async throws {
        let library = OfflineLibrary(directory: temporaryDirectory())
        let source = OfflineSourceStub(info: try readerInfo(
            mode: "txt", delivery: "client_full",
            offline: #"{"kind":"content","max_age_days":30}"#
        ))

        try await library.save(fileID: fileID, from: source)

        let text = await library.text(fileID: fileID)
        XCTAssertEqual(text?.body, "Тестовий текст")
    }

    func testNothingIsKeptWithoutTheRight() async throws {
        let library = OfflineLibrary(directory: temporaryDirectory())
        let source = OfflineSourceStub(info: try fixtureInfo())

        do {
            try await library.save(fileID: fileID, from: source)
            XCTFail("Must not save without can_save_offline")
        } catch {
            XCTAssertEqual(error as? OfflineSaveError, .notAllowed)
        }
        let copies = await library.copies()
        XCTAssertTrue(copies.isEmpty)
    }

    func testTheSizeCapStopsASaveAndLeavesNothing() async throws {
        let directory = temporaryDirectory()
        let library = OfflineLibrary(directory: directory, capacity: 10)
        let source = OfflineSourceStub(info: try readerInfo(
            mode: "pdf", delivery: "client_full",
            offline: #"{"kind":"pages","total_pages":3,"max_age_days":30}"#
        ))

        do {
            try await library.save(fileID: fileID, from: source)
            XCTFail("Must not exceed the cap")
        } catch {
            XCTAssertEqual(error as? OfflineSaveError, .storageFull)
        }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testCopiesExpireAfterMaxAgeWithoutOpening() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_792_000_000))
        let library = OfflineLibrary(directory: temporaryDirectory(), now: { clock.now })
        let source = OfflineSourceStub(info: try readerInfo(
            mode: "txt", delivery: "client_full",
            offline: #"{"kind":"content","max_age_days":30}"#
        ))
        try await library.save(fileID: fileID, from: source)

        clock.advance(days: 29)
        var evicted = await library.evictExpired()
        XCTAssertTrue(evicted.isEmpty)
        await library.noteOpened(fileID: fileID)

        clock.advance(days: 29)
        evicted = await library.evictExpired()
        XCTAssertTrue(evicted.isEmpty, "Opening restarted the window")

        clock.advance(days: 2)
        evicted = await library.evictExpired()
        XCTAssertEqual(evicted, [fileID])
    }

    func testRevalidationRemovesDisallowedCopiesAndFlagsChangedOnes() async throws {
        let library = OfflineLibrary(directory: temporaryDirectory())
        let other = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let info = try readerInfo(mode: "txt", delivery: "client_full", offline: #"{"kind":"content","max_age_days":30}"#)
        try await library.save(fileID: fileID, from: OfflineSourceStub(info: info))
        try await library.save(fileID: other, from: OfflineSourceStub(info: info))

        var checker = StatusStub(statuses: [
            OfflineFileStatus(id: fileID.uuidString.lowercased(), canSaveOffline: true, canRead: true, updatedAt: "A"),
            OfflineFileStatus(id: other.uuidString.lowercased(), canSaveOffline: false, canRead: true, updatedAt: "A"),
        ])
        var result = try await library.revalidate(using: checker)
        XCTAssertEqual(result.removed, [other])
        XCTAssertTrue(result.stale.isEmpty, "The first check only records the version")

        checker = StatusStub(statuses: [
            OfflineFileStatus(id: fileID.uuidString.lowercased(), canSaveOffline: true, canRead: true, updatedAt: "B"),
        ])
        result = try await library.revalidate(using: checker)
        XCTAssertEqual(result.stale, [fileID])
        let copies = await library.copies()
        XCTAssertEqual(copies.map(\.fileID), [fileID])
    }

    func testCopiesSurviveARelaunch() async throws {
        let directory = temporaryDirectory()
        let info = try readerInfo(mode: "txt", delivery: "client_full", offline: #"{"kind":"content","max_age_days":30}"#)
        try await OfflineLibrary(directory: directory).save(fileID: fileID, from: OfflineSourceStub(info: info))

        let relaunched = OfflineLibrary(directory: directory)
        let copies = await relaunched.copies()
        XCTAssertEqual(copies.map(\.title), ["Енеїда"])
    }

    // MARK: - Fixtures

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func fixtureInfo() throws -> ReaderInfo {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "reader-info-text", withExtension: "json"))
        return try JSONDecoder().decode(ReaderInfo.self, from: Data(contentsOf: url))
    }

    private func readerInfo(mode: String, delivery: String, offline: String) throws -> ReaderInfo {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "reader-info-text", withExtension: "json"))
        var json = try String(contentsOf: url, encoding: .utf8)
        json = json.replacingOccurrences(of: "\"rendering_mode\": \"txt\"", with: "\"rendering_mode\": \"\(mode)\"")
        json = json.replacingOccurrences(of: "\"page_delivery\": \"client_full\"", with: "\"page_delivery\": \"\(delivery)\", \"offline\": \(offline)")
        json = json.replacingOccurrences(of: "\"restriction_reason\": null", with: "\"restriction_reason\": null, \"can_save_offline\": true")
        return try JSONDecoder().decode(ReaderInfo.self, from: Data(json.utf8))
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(days: Int) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(TimeInterval(days) * 86_400)
    }
}

private struct StatusStub: OfflineStatusChecking {
    let statuses: [OfflineFileStatus]
    func offlineStatus(fileIDs: [UUID]) async throws -> [OfflineFileStatus] { statuses }
}

/// A reader source that answers with canned content; `info` nil behaves as
/// an unreachable network.
private actor OfflineSourceStub: ReaderRepository {
    let infoValue: ReaderInfo?
    private(set) var pageRequests: [Int] = []

    init(info: ReaderInfo?) {
        infoValue = info
    }

    func info(fileID: UUID) async throws -> ReaderInfo {
        guard let infoValue else { throw APIError.transport }
        return infoValue
    }

    func text(fileID: UUID) async throws -> TextReaderContent {
        try JSONDecoder().decode(TextReaderContent.self, from: Data(#"{"body":"Тестовий текст","page_offsets":[]}"#.utf8))
    }

    func epubDocument(fileID: UUID) async throws -> Data { throw APIError.transport }
    func fullDocument(fileID: UUID) async throws -> Data { throw APIError.transport }
    func pagePDF(fileID: UUID, page: Int) async throws -> Data { throw APIError.transport }

    func pageImage(fileID: UUID, page: Int, width: Int) async throws -> Data {
        guard infoValue != nil else { throw APIError.transport }
        pageRequests.append(page)
        return Data("page-\(page)".utf8)
    }

    func savePosition(
        fileID: UUID,
        positionType: String,
        positionValue: String,
        progressPercent: Int?,
        totalPages: Int?
    ) async throws -> Bool { true }
}
