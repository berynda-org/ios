import Foundation
import UIKit
import XCTest
import BeryndaCore
@testable import Berynda

/// Plain-text and Markdown books read a screen page at a time. Their place —
/// the reading position and any bookmark — is a UTF-16 offset into the body
/// (`char`), the unit the web reader stores, never the screen page number.
@MainActor
final class TextReaderPagingTests: XCTestCase {
    private let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    // MARK: - Pagination

    func testPaginationCoversTheWholeBodyInScreenPages() throws {
        let body = String(
            repeating: "Тіні забутих предків 👍🏽 — и\u{0306}ого. " + String(repeating: "Текст для читання. ", count: 12) + "\r\n",
            count: 80
        )
        let metrics = TextPageMetrics(pane: CGSize(width: 390, height: 640), fontSize: 19, lineSpacing: 7)
        let layout = try TextPaginator.layout(body: body, isMarkdown: false, metrics: metrics) { _ in }

        XCTAssertGreaterThan(layout.pageCount, 5)
        XCTAssertEqual(layout.pageMap.pageCount, layout.pageCount)
        XCTAssertEqual(layout.pageMap.textLength, body.utf16.count)
        XCTAssertEqual(layout.attributedText.string, body, "Plain text must be drawn untouched")

        // Pages are contiguous and together hold every character once.
        var expected = 0
        for range in layout.renderedRanges {
            XCTAssertEqual(range.location, expected)
            XCTAssertGreaterThan(range.length, 0)
            expected = NSMaxRange(range)
        }
        XCTAssertEqual(expected, body.utf16.count)
        // For plain text the stored starts are the drawn starts.
        XCTAssertEqual(layout.pageMap.pageStarts, layout.renderedRanges.map(\.location))

        // Every page fits the page it is drawn on.
        for page in 1...layout.pageCount {
            let height = layout.text(ofPage: page).boundingRect(
                with: CGSize(width: metrics.textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).height
            XCTAssertLessThanOrEqual(height, metrics.textHeight + metrics.lineSpacing + 1, "page \(page)")
        }
    }

    func testLargerTextMakesMorePages() throws {
        let body = String(repeating: "Сторінка тексту для перевірки. ", count: 600)
        let pane = CGSize(width: 390, height: 640)
        let small = try TextPaginator.layout(
            body: body,
            isMarkdown: false,
            metrics: TextPageMetrics(pane: pane, fontSize: 17, lineSpacing: 6)
        ) { _ in }
        let large = try TextPaginator.layout(
            body: body,
            isMarkdown: false,
            metrics: TextPageMetrics(pane: pane, fontSize: 26, lineSpacing: 9)
        ) { _ in }

        XCTAssertGreaterThan(large.pageCount, small.pageCount)
    }

    func testMarkdownPagesStartAtSourceOffsets() throws {
        let paragraph = "**Розділ** з _курсивом_ і `кодом`. " + String(repeating: "Звичайне речення. ", count: 20) + "\n"
        let body = String(repeating: paragraph, count: 60)
        let metrics = TextPageMetrics(pane: CGSize(width: 390, height: 640), fontSize: 19, lineSpacing: 7)
        let layout = try TextPaginator.layout(body: body, isMarkdown: true, metrics: metrics) { _ in }

        XCTAssertGreaterThan(layout.pageCount, 2)
        XCTAssertLessThan(layout.attributedText.length, body.utf16.count, "Markup is not drawn")
        XCTAssertEqual(layout.pageMap.textLength, body.utf16.count)
        XCTAssertEqual(layout.pageMap.pageStarts.first, 0)
        // Source starts never run backwards and stay inside the body.
        XCTAssertEqual(layout.pageMap.pageStarts, layout.pageMap.pageStarts.sorted())
        XCTAssertLessThanOrEqual(layout.pageMap.pageStarts.last ?? 0, body.utf16.count)
        // Bold survives as a real font trait, not as asterisks.
        let font = layout.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
    }

    func testCancelledPaginationStops() async {
        let body = String(repeating: "Довгий текст. ", count: 50_000)
        let metrics = TextPageMetrics(pane: CGSize(width: 390, height: 640), fontSize: 19, lineSpacing: 7)
        let task = Task.detached {
            try TextPaginator.layout(body: body, isMarkdown: false, metrics: metrics) { _ in }
        }
        task.cancel()
        do {
            _ = try await task.value
            // Finishing before the cancellation landed is also acceptable.
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    // MARK: - Position

    func testTextBookOpensPagedAndSavesACharPosition() async throws {
        let body = "Перша сторінка. Друга сторінка. Третя сторінка."
        let repository = TextPositionStub(body: body)
        let (model, store) = try await makeModel(repository: repository)

        XCTAssertTrue(model.isReflowableText)
        XCTAssertTrue(model.isTextPaged)
        XCTAssertTrue(model.usesLayoutPaging)
        XCTAssertNil(model.navigablePageCount, "No page count before the view paginates")
        XCTAssertFalse(model.canGoForward)

        model.applyTextLayout(TextPageMap(pageStarts: [0, 16, 32], textLength: body.utf16.count))
        XCTAssertEqual(model.navigablePageCount, 3)
        XCTAssertEqual(model.currentPage, 1)
        XCTAssertTrue(model.canGoForward)
        XCTAssertNil(model.pageLabel(for: 1))

        model.selectPage(2)
        await model.flushPosition()

        let saves = await repository.saves
        XCTAssertEqual(saves.last?.type, "char")
        XCTAssertEqual(saves.last?.value, "16")
        XCTAssertEqual(saves.last?.progress, Int((16.0 / Double(body.utf16.count) * 100).rounded()))
        XCTAssertNil(saves.last?.totalPages, "Screen pages differ per device and are not sent")
        XCTAssertFalse(saves.contains { $0.type == "page" })

        let local = await store.position(for: fileID)
        XCTAssertEqual(local?.charOffset, 16)
        XCTAssertEqual(model.bookmarkCharOffset, 16)
    }

    func testRemoteCharPositionOpensOnThePageHoldingIt() async throws {
        let body = String(repeating: "абвгд", count: 10)
        let repository = TextPositionStub(
            body: body,
            readingPosition: #"{"position_type":"char","position_value":"27","progress_percent":54,"total_pages":null,"last_read_at":null}"#
        )
        let (model, _) = try await makeModel(repository: repository)

        XCTAssertEqual(model.textOffset, 27)
        model.applyTextLayout(TextPageMap(pageStarts: [0, 10, 20, 30, 40], textLength: 50))
        XCTAssertEqual(model.currentPage, 3)

        // A re-pagination (rotation, larger text) keeps the same offset.
        model.applyTextLayout(TextPageMap(pageStarts: [0, 25, 50], textLength: 50))
        XCTAssertEqual(model.currentPage, 2)
        XCTAssertEqual(model.textOffset, 27)
    }

    func testLegacyPagePositionOfAPlainTextIsIgnored() async throws {
        // Older builds wrote page 1 for every text book; it is no place.
        let repository = TextPositionStub(
            body: String(repeating: "абвгд", count: 10),
            readingPosition: #"{"position_type":"page","position_value":"4","progress_percent":null,"total_pages":null,"last_read_at":null}"#
        )
        let (model, _) = try await makeModel(repository: repository)

        XCTAssertEqual(model.textOffset, 0)
        model.applyTextLayout(TextPageMap(pageStarts: [0, 10, 20, 30, 40], textLength: 50))
        XCTAssertEqual(model.currentPage, 1)
    }

    func testCharLinkWinsOverTheStoredPosition() async throws {
        let repository = TextPositionStub(
            body: String(repeating: "абвгд", count: 10),
            readingPosition: #"{"position_type":"char","position_value":"5","progress_percent":10,"total_pages":null,"last_read_at":null}"#
        )
        let (model, _) = try await makeModel(repository: repository, initialCharOffset: 44)

        model.applyTextLayout(TextPageMap(pageStarts: [0, 10, 20, 30, 40], textLength: 50))
        XCTAssertEqual(model.currentPage, 5)
    }

    func testCharPositionOpensTheServerPageOfAPaginatedText() async throws {
        let body = "Сторінка перша. Сторінка друга. Сторінка третя."
        let repository = TextPositionStub(
            body: body,
            pageOffsets: [0, 16, 32],
            readingPosition: #"{"position_type":"char","position_value":"20","progress_percent":40,"total_pages":null,"last_read_at":null}"#
        )
        let (model, _) = try await makeModel(repository: repository)

        XCTAssertFalse(model.isReflowableText)
        XCTAssertEqual(model.currentPage, 2)
        guard case let .text(page, _) = try XCTUnwrap(model.content) else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(page, "Сторінка друга. ")
    }

    func testContinuousModeKeepsTheOffsetAndSavesTheScrolledPlace() async throws {
        let body = String(repeating: "абвгд", count: 10)
        let repository = TextPositionStub(body: body)
        let (model, _) = try await makeModel(repository: repository)
        model.applyTextLayout(TextPageMap(pageStarts: [0, 10, 20, 30, 40], textLength: 50))
        model.selectPage(3)

        model.setTextPaged(false)
        XCTAssertFalse(model.usesLayoutPaging)
        XCTAssertEqual(model.textOffset, 20)

        model.textDidScroll(to: 41)
        await model.flushPosition()
        let saves = await repository.saves
        XCTAssertEqual(saves.last?.type, "char")
        XCTAssertEqual(saves.last?.value, "41")

        model.setTextPaged(true)
        XCTAssertEqual(model.currentPage, 5)
    }

    // MARK: - Bookmarks

    func testTextBookmarkIsStoredAsACharPosition() async throws {
        let repository = BookmarkRecordingStub()
        let library = try await makeLibrary(repository: repository)

        let saved = await library.quickAdd(fileID: fileID, page: 3, charOffset: 1_234)
        XCTAssertEqual(saved, .saved)
        let calls = await repository.calls
        XCTAssertEqual(calls, [
            BookmarkCall(positionType: "char", positionValue: "1234", pageNumber: 3),
        ])

        // The same offset is the same bookmark, whatever page it was on.
        let again = await library.quickAdd(fileID: fileID, page: 7, charOffset: 1_234)
        XCTAssertEqual(again, .alreadySaved)
        // A page bookmark still records a page.
        let page = await library.quickAdd(fileID: fileID, page: 9)
        XCTAssertEqual(page, .saved)
        let after = await repository.calls
        XCTAssertEqual(after.last, BookmarkCall(positionType: "page", positionValue: "9", pageNumber: 9))
    }

    func testPendingTextBookmarkResumesAfterSignIn() async {
        let environment = AppEnvironment.uiTesting()
        environment.requireAuthentication(for: .bookmark(fileID: fileID, page: 2, charOffset: 40))

        let signedIn = await environment.account.signIn(email: "reader@example.org", password: "password123")
        XCTAssertTrue(signedIn)
        await environment.resumePendingAuthenticatedAction()

        XCTAssertEqual(environment.authenticatedActionMessage, "Закладку додано до бібліографічного списку.")
    }

    func testCharLinkReachesTheReaderPresentation() {
        let environment = AppEnvironment.uiTesting()
        environment.open(URL(string: "https://berynda.org/read/44444444-4444-4444-4444-444444444444?char=512")!)
        environment.consumePendingRoute()

        XCTAssertEqual(environment.presentedReader?.fileID, fileID)
        XCTAssertEqual(environment.presentedReader?.initialCharOffset, 512)
        XCTAssertNil(environment.presentedReader?.initialPage)
    }

    // MARK: - Fixtures

    private func makeModel(
        repository: TextPositionStub,
        initialCharOffset: Int? = nil
    ) async throws -> (ReaderViewModel, LocalReadingPositionStore) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextReaderPagingTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LocalReadingPositionStore(directory: directory)
        let account = try await signedInAccount(store: store, directory: directory)
        let model = ReaderViewModel(
            fileID: fileID,
            initialCharOffset: initialCharOffset,
            repository: repository,
            session: account.session,
            account: account.model,
            localPositions: store
        )
        await model.load()
        return (model, store)
    }

    private func makeLibrary(repository: BookmarkRecordingStub) async throws -> LibraryViewModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextReaderPagingTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LocalReadingPositionStore(directory: directory.appendingPathComponent("positions", isDirectory: true))
        let account = try await signedInAccount(store: store, directory: directory)
        return LibraryViewModel(repository: repository, account: account.model)
    }

    private func signedInAccount(
        store: LocalReadingPositionStore,
        directory: URL
    ) async throws -> (session: SessionController, model: AccountViewModel) {
        let authentication = UITestAuthenticationService()
        let session = SessionController(tokenStore: UITestTokenStore(), authentication: authentication)
        let account = AccountViewModel(
            session: session,
            authentication: authentication,
            repository: UITestAccountRepository(),
            localPositions: store,
            recentlyViewed: RecentlyViewedStore(
                directory: directory.appendingPathComponent("recently-viewed", isDirectory: true)
            )
        )
        let signedIn = await account.signIn(email: "reader@example.org", password: "password123")
        XCTAssertTrue(signedIn)
        return (session, account)
    }
}

private struct PositionSave: Sendable {
    let type: String
    let value: String
    let progress: Int?
    let totalPages: Int?
}

private actor TextPositionStub: ReaderRepository {
    private let body: String
    private let pageOffsets: [Int]
    private let readingPosition: String
    private(set) var saves: [PositionSave] = []

    init(body: String, pageOffsets: [Int] = [], readingPosition: String = "null") {
        self.body = body
        self.pageOffsets = pageOffsets
        self.readingPosition = readingPosition
    }

    func info(fileID: UUID) async throws -> ReaderInfo {
        let json = """
        {
          "file_id": "44444444-4444-4444-4444-444444444444",
          "edition_id": "33333333-3333-3333-3333-333333333333",
          "work_id": "11111111-1111-1111-1111-111111111111",
          "book": {"title": "Енеїда", "authors": []},
          "mime_type": "text/plain",
          "rendering_mode": "txt",
          "page_delivery": "client_full",
          "pages_extracted": false,
          "split_pending": false,
          "split_failed": false,
          "has_toc": false,
          "total_pages": null,
          "access_mode": "read_only",
          "download_allowed": false,
          "toc": [],
          "reading_position": \(readingPosition),
          "rights": {
            "can_read": true,
            "can_download_file": false,
            "can_download_page": false,
            "can_copy_text": true,
            "can_print": false,
            "can_share": true,
            "restriction_reason": null
          },
          "page_labels": []
        }
        """
        return try JSONDecoder().decode(ReaderInfo.self, from: Data(json.utf8))
    }

    func text(fileID: UUID) async throws -> TextReaderContent {
        let data = try JSONSerialization.data(withJSONObject: ["body": body, "page_offsets": pageOffsets] as [String: Any])
        return try JSONDecoder().decode(TextReaderContent.self, from: data)
    }

    func epubDocument(fileID: UUID) async throws -> Data { throw StubError.unsupported }
    func fullDocument(fileID: UUID) async throws -> Data { throw StubError.unsupported }
    func pagePDF(fileID: UUID, page: Int) async throws -> Data { throw StubError.unsupported }
    func pageImage(fileID: UUID, page: Int, width: Int) async throws -> Data { throw StubError.unsupported }

    func savePosition(
        fileID: UUID,
        positionType: String,
        positionValue: String,
        progressPercent: Int?,
        totalPages: Int?
    ) async throws -> Bool {
        saves.append(PositionSave(type: positionType, value: positionValue, progress: progressPercent, totalPages: totalPages))
        return true
    }

    enum StubError: Error {
        case unsupported
    }
}

private struct BookmarkCall: Equatable, Sendable {
    let positionType: String?
    let positionValue: String?
    let pageNumber: Int?
}

/// One list that keeps what quick add files into it, the way the server does.
private actor BookmarkRecordingStub: LibraryRepository {
    private(set) var calls: [BookmarkCall] = []
    private var items: [[String: Any]] = []
    private let listID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!

    enum StubError: Error {
        case unsupported
    }

    func continueReading(limit: Int) async throws -> ContinueReadingResponse {
        ContinueReadingResponse(recentlyRead: [], historyEnabled: true)
    }

    func bibliographyLists() async throws -> [BibliographyList] {
        let list: [String: Any] = [
            "id": listID.uuidString.lowercased(),
            "title": "Закладки",
            "description": "",
            "citation_style": "dstu_8302_2015",
            "visibility": "private",
            "is_pinned": false,
            "work_count": items.count,
            "items": items,
        ]
        return [try JSONDecoder().decode(BibliographyList.self, from: JSONSerialization.data(withJSONObject: list))]
    }

    func createList(title: String) async throws -> BibliographyList { throw StubError.unsupported }
    func renameList(id: UUID, title: String) async throws -> BibliographyList { throw StubError.unsupported }
    func deleteList(id: UUID) async throws { throw StubError.unsupported }
    func removeItem(listID: UUID, itemID: UUID) async throws { throw StubError.unsupported }
    func addWork(_ workID: UUID, toList listID: UUID) async throws -> BibliographyItem { throw StubError.unsupported }

    func quickAdd(
        workID: UUID?,
        fileID: UUID?,
        positionType: String?,
        positionValue: String?,
        pageNumber: Int?
    ) async throws -> BibliographyItem {
        calls.append(BookmarkCall(positionType: positionType, positionValue: positionValue, pageNumber: pageNumber))
        var item: [String: Any] = [
            "id": UUID().uuidString.lowercased(),
            "work": UUID(uuidString: "11111111-1111-1111-1111-111111111111")!.uuidString.lowercased(),
            "work_title": "Енеїда",
            "note": "",
        ]
        if let fileID { item["file"] = fileID.uuidString.lowercased() }
        if let positionType { item["position_type"] = positionType }
        if let positionValue { item["position_value"] = positionValue }
        if let pageNumber { item["page_number"] = pageNumber }
        items.append(item)
        return try JSONDecoder().decode(BibliographyItem.self, from: JSONSerialization.data(withJSONObject: item))
    }

    func publicCollections() async throws -> [PublicCollectionSummary] { [] }
    func savedCollections() async throws -> [PublicCollectionSummary] { [] }
    func setCollectionSaved(slug: String, saved: Bool) async throws {}
}
