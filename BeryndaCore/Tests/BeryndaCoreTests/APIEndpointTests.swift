import Foundation
import XCTest
@testable import BeryndaCore

final class APIEndpointTests: XCTestCase {
    private let baseURL = URL(string: "https://berynda.org/api/v1/")!
    private let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    func testReaderInfoURLIsAbsoluteAndPreservesBasePath() throws {
        let url = try XCTUnwrap(APIEndpoint.readerInfo(fileID: fileID).url(relativeTo: baseURL))

        XCTAssertEqual(url.baseURL, nil)
        XCTAssertEqual(
            url.absoluteString,
            "https://berynda.org/api/v1/files/44444444-4444-4444-4444-444444444444/reader-info/"
        )
    }

    func testPageImageClampsParametersOnAbsoluteURL() throws {
        let url = try XCTUnwrap(
            APIEndpoint.pageImage(fileID: fileID, page: -9, width: 9_000)
                .url(relativeTo: baseURL)
        )
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )

        XCTAssertEqual(
            components.path,
            "/api/v1/files/44444444-4444-4444-4444-444444444444/pages/1/"
        )
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "width" })?.value,
            "2000"
        )
    }

    func testWorkURLUsesTheAPIWorkDetailPath() throws {
        let url = try XCTUnwrap(APIEndpoint.work(slug: "eneida").url(relativeTo: baseURL))

        XCTAssertEqual(
            url.absoluteString,
            "https://berynda.org/api/v1/works/eneida/"
        )
    }

    func testWorksSearchUsesTheCatalogPrefixFilterAndPage() throws {
        let url = try XCTUnwrap(
            APIEndpoint.works(search: "  Енеїда  ", page: 3).url(relativeTo: baseURL)
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.path, "/api/v1/works/")
        XCTAssertEqual(query["page"]!, "3")
        XCTAssertEqual(query["q"]!, "Енеїда")
        XCTAssertFalse(query.keys.contains("search"))
    }

    func testFilteredWorksUsesSupportedBackendParameters() throws {
        let url = try XCTUnwrap(
            APIEndpoint.worksFiltered(
                search: "Кобзар",
                page: 2,
                readableOnly: true,
                language: "uk"
            ).url(relativeTo: baseURL)
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(query["q"]!, "Кобзар")
        XCTAssertEqual(query["page"]!, "2")
        XCTAssertEqual(query["mobile_readable"]!, "true")
        XCTAssertEqual(query["language"]!, "uk")
    }

    func testWorkIdentifierCannotInjectAnotherPathSegment() throws {
        let url = try XCTUnwrap(
            APIEndpoint.work(slug: "folder/name%2Fchild").url(relativeTo: baseURL)
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://berynda.org/api/v1/works/folder%2Fname%252Fchild/"
        )
    }
    func testWorkCollectionsPath() throws {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let url = try XCTUnwrap(
            APIEndpoint.workCollections(workID: id).url(relativeTo: baseURL)
        )
        XCTAssertEqual(
            url.absoluteString,
            "https://berynda.org/api/v1/works/11111111-1111-1111-1111-111111111111/collections/"
        )
    }

    func testRecommendedWorksClampsItsLimit() throws {
        func limit(_ requested: Int) throws -> String? {
            let url = try XCTUnwrap(
                APIEndpoint.recommendedWorks(limit: requested).url(relativeTo: baseURL)
            )
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "limit" })?.value
        }

        XCTAssertEqual(try limit(12), "12")
        // Clamped here as well as on the server, so a caller cannot send a
        // request the server will only reject or silently bound.
        XCTAssertEqual(try limit(9_999), "48")
        XCTAssertEqual(try limit(0), "1")
        XCTAssertEqual(try limit(-5), "1")
    }

    func testAuthorWorksArePaginatedAndCanBeFiltered() throws {
        let url = try XCTUnwrap(APIEndpoint.authorWorks(id: fileID, page: 2, readableOnly: true).url(relativeTo: baseURL))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(parts.path, "/api/v1/works/")
        XCTAssertEqual(query["person_id"]!, fileID.uuidString.lowercased())
        XCTAssertEqual(query["page"]!, "2")
        XCTAssertEqual(query["mobile_readable"]!, "true")
        XCTAssertEqual(APIEndpoint.author(id: fileID).url(relativeTo: baseURL)?.absoluteString,
                       "https://berynda.org/api/v1/persons/44444444-4444-4444-4444-444444444444/")
    }

}
