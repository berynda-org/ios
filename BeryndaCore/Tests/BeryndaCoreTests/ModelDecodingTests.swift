import XCTest
@testable import BeryndaCore

final class ModelDecodingTests: XCTestCase {
    func testWorkPageFixtureDecodes() throws {
        let page: PaginatedResponse<WorkSummary> = try decode("works-page")
        XCTAssertEqual(page.count, 1)
        XCTAssertEqual(page.results.first?.title, "Енеїда")
        XCTAssertEqual(page.results.first?.authors.first?.displayName, "Іван Котляревський")
        XCTAssertTrue(page.results.first?.hasTextFile == true)
    }

    func testEditionFixtureUsesCanonicalFileWithoutFormat() throws {
        let page: PaginatedResponse<EditionSummary> = try decode("editions-page")
        let edition = try XCTUnwrap(page.results.first)
        XCTAssertEqual(edition.readableFileID?.uuidString.lowercased(), "44444444-4444-4444-4444-444444444444")
        XCTAssertTrue(edition.canRead)
        XCTAssertFalse(edition.canDownload)
    }

    func testReaderInfoFixtureDecodesMobileRendererContract() throws {
        let info: ReaderInfo = try decode("reader-info-text")
        XCTAssertEqual(info.renderingMode, .text)
        XCTAssertEqual(info.book.title, "Енеїда")
        XCTAssertTrue(info.rights.canRead)
        XCTAssertEqual(info.pageLabels.first?.label, "Обкладинка")
    }

    func testRestrictedClientPDFHintFallsBackToRenderedPage() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "reader-info-text", withExtension: "json"))
        var json = try String(contentsOf: url, encoding: .utf8)
        json = json.replacingOccurrences(of: "\"rendering_mode\": \"txt\"", with: "\"rendering_mode\": \"pdf\"")
        json = json.replacingOccurrences(of: "\"mime_type\": \"text/plain\"", with: "\"mime_type\": \"application/pdf\"")
        let info = try JSONDecoder().decode(ReaderInfo.self, from: Data(json.utf8))

        XCTAssertEqual(info.pageDelivery, .clientFull)
        XCTAssertFalse(info.rights.canDownloadFile)
        XCTAssertEqual(info.resource, .pageImage)
    }

    func testDjVuServedAsServerPagesReadsAsPageImages() throws {
        let info = try readerInfo(renderingMode: "djvu", pageDelivery: "server_pages")

        XCTAssertEqual(info.renderingMode, .djvu)
        XCTAssertEqual(info.resource, .pageImage)
        XCTAssertTrue(info.isPagedDocument)
    }

    func testDjVuWithAnyOtherDeliveryStaysUnsupported() throws {
        for delivery in ["client_full", "client_per_page"] {
            let info = try readerInfo(renderingMode: "djvu", pageDelivery: delivery)

            XCTAssertEqual(info.resource, .unsupported, "djvu + \(delivery)")
            XCTAssertFalse(info.isPagedDocument, "djvu + \(delivery)")
        }
    }

    func testOnlyDocumentsReadPageByPage() throws {
        XCTAssertFalse(try readerInfo(renderingMode: "txt", pageDelivery: "client_full").isPagedDocument)
        XCTAssertFalse(try readerInfo(renderingMode: "epub", pageDelivery: "client_full").isPagedDocument)
        XCTAssertTrue(try readerInfo(renderingMode: "pdf", pageDelivery: "client_per_page").isPagedDocument)
    }

    private func readerInfo(renderingMode: String, pageDelivery: String) throws -> ReaderInfo {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "reader-info-text", withExtension: "json"))
        var json = try String(contentsOf: url, encoding: .utf8)
        json = json.replacingOccurrences(of: "\"rendering_mode\": \"txt\"", with: "\"rendering_mode\": \"\(renderingMode)\"")
        json = json.replacingOccurrences(of: "\"page_delivery\": \"client_full\"", with: "\"page_delivery\": \"\(pageDelivery)\"")
        return try JSONDecoder().decode(ReaderInfo.self, from: Data(json.utf8))
    }

    private func decode<T: Decodable>(_ name: String) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    func testCollectionSummarySurvivesANullDescription() throws {
        // `Collection.description` is a nullable column the API serialises
        // verbatim, so one collection without a description must not fail the
        // whole response and empty the shelf.
        let json = #"""
        {
          "id": "77777777-7777-7777-7777-777777777777",
          "slug": "poetry",
          "name": "Поезія",
          "description": null,
          "category": null,
          "is_featured": true,
          "cover_image_url": null,
          "work_count": 3,
          "featured_works": []
        }
        """#
        let collection = try JSONDecoder().decode(
            PublicCollectionSummary.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(collection.slug, "poetry")
        XCTAssertEqual(collection.description, "")
        XCTAssertEqual(collection.category, "")
        XCTAssertTrue(collection.isFeatured)
    }

    func testNewListWithoutDescriptionOrNoteDecodes() throws {
        // `POST /lists/` with a title only stores `description` as null, and
        // an item can carry a null `note`. Failing on either broke the create
        // response and every library load after it.
        let json = #"""
        {
          "id": "88888888-8888-8888-8888-888888888888",
          "owner": "99999999-9999-9999-9999-999999999999",
          "title": "Нове",
          "description": null,
          "citation_style": "dstu_8302",
          "visibility": "private",
          "is_pinned": false,
          "work_count": 1,
          "items": [{
            "id": "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
            "work": "11111111-1111-1111-1111-111111111111",
            "edition": null,
            "file": null,
            "note": null
          }],
          "created_at": "2026-10-22T10:00:00Z",
          "updated_at": "2026-10-22T10:00:00Z"
        }
        """#
        let list = try JSONDecoder().decode(BibliographyList.self, from: Data(json.utf8))

        XCTAssertEqual(list.title, "Нове")
        XCTAssertEqual(list.description, "")
        XCTAssertEqual(list.items.first?.note, "")
    }

}
