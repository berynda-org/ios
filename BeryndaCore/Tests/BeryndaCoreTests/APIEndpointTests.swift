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
                filters: WorkFilters(
                    readableOnly: true,
                    language: "uk",
                    workType: "book",
                    yearFrom: 1900,
                    yearTo: 1850,
                    topic: TopicReference(slug: "poeziia", name: "Поезія")
                )
            ).url(relativeTo: baseURL)
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.path, "/api/v1/works/")
        XCTAssertEqual(query["q"]!, "Кобзар")
        XCTAssertEqual(query["page"]!, "2")
        XCTAssertEqual(query["mobile_readable"]!, "true")
        XCTAssertEqual(query["language"]!, "uk")
        XCTAssertEqual(query["work_type"]!, "book")
        // A range typed back to front is sent the right way round.
        XCTAssertEqual(query["year_from"]!, "1850")
        XCTAssertEqual(query["year_to"]!, "1900")
        XCTAssertEqual(query["topic"]!, "poeziia")
    }

    func testUnfilteredWorksSendOnlyTheSearchAndPage() throws {
        let url = try XCTUnwrap(
            APIEndpoint.worksFiltered(search: "  ", page: 0, filters: WorkFilters()).url(relativeTo: baseURL)
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.queryItems?.map(\.name), ["page"])
        XCTAssertEqual(components.queryItems?.first?.value, "1")
    }

    func testFacetsTakeTheWorksFiltersWithoutAPage() throws {
        let url = try XCTUnwrap(
            APIEndpoint.workFacets(
                search: "Шевченко",
                filters: WorkFilters(readableOnly: true, topic: TopicReference(slug: "poeziia", name: "Поезія"))
            ).url(relativeTo: baseURL)
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.path, "/api/v1/works/facets/")
        XCTAssertEqual(query["q"]!, "Шевченко")
        XCTAssertEqual(query["mobile_readable"]!, "true")
        XCTAssertEqual(query["topic"]!, "poeziia")
        XCTAssertFalse(query.keys.contains("page"))
    }

    func testCrossSearchAsksForPeopleAndPeriodicalsWithABoundedLimit() throws {
        let url = try XCTUnwrap(
            APIEndpoint.crossSearch(query: " Шевченко ", types: ["person", "periodical"], limit: 500)
                .url(relativeTo: baseURL)
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.path, "/api/v1/search/cross/")
        XCTAssertEqual(query["q"]!, "Шевченко")
        XCTAssertEqual(query["types"]!, "person,periodical")
        XCTAssertEqual(query["limit"]!, "20")
    }

    func testPeriodicalEndpointsUseTheCatalogPaths() throws {
        func url(_ endpoint: APIEndpoint) throws -> String {
            try XCTUnwrap(endpoint.url(relativeTo: baseURL)).absoluteString
        }
        let issueID = UUID(uuidString: "77777777-1925-0000-0000-000000000001")!
        let workID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        XCTAssertEqual(try url(.periodicals(search: " Веселка ", page: 2)),
                       "https://berynda.org/api/v1/periodicals/?page=2&search=%D0%92%D0%B5%D1%81%D0%B5%D0%BB%D0%BA%D0%B0")
        XCTAssertEqual(try url(.periodical(identifier: "veselka")), "https://berynda.org/api/v1/periodicals/veselka/")
        XCTAssertEqual(try url(.periodicalYears(identifier: "veselka")), "https://berynda.org/api/v1/periodicals/veselka/years/")
        XCTAssertEqual(try url(.periodicalIssues(identifier: "veselka", year: 1984)),
                       "https://berynda.org/api/v1/periodicals/veselka/issues/?year=1984")
        XCTAssertEqual(try url(.periodicalIssueWorks(issueID: issueID, page: 1, readableOnly: true)),
                       "https://berynda.org/api/v1/periodical-issues/77777777-1925-0000-0000-000000000001/works/?page=1&mobile_readable=true")
        XCTAssertEqual(try url(.periodicalIssueWorks(issueID: issueID, page: 3, readableOnly: false)),
                       "https://berynda.org/api/v1/periodical-issues/77777777-1925-0000-0000-000000000001/works/?page=3")
        XCTAssertEqual(try url(.workPeriodicalIssues(workID: workID)),
                       "https://berynda.org/api/v1/works/11111111-1111-1111-1111-111111111111/periodical-issues/")
    }

    func testTopicsListAsksForRootsAndSearchesByName() throws {
        let roots = try XCTUnwrap(
            APIEndpoint.topics(parent: "root", search: nil, page: 2).url(relativeTo: baseURL)
        )
        XCTAssertEqual(roots.absoluteString, "https://berynda.org/api/v1/topics/?page=2&parent=root")

        let search = try XCTUnwrap(
            APIEndpoint.topics(parent: nil, search: " історія ", page: 1).url(relativeTo: baseURL)
        )
        let components = try XCTUnwrap(URLComponents(url: search, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(query["search"]!, "історія")
        XCTAssertFalse(query.keys.contains("parent"))

        XCTAssertEqual(
            APIEndpoint.topic(slug: "shkilni-pidruchnyky").url(relativeTo: baseURL)?.absoluteString,
            "https://berynda.org/api/v1/topics/shkilni-pidruchnyky/"
        )
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
