import BeryndaCore
import XCTest
@testable import Berynda

@MainActor
final class AuthorViewModelTests: XCTestCase {
    func testPaginationRetryAndReadingFilterReplaceTheCorrectWorks() async throws {
        let repository = AuthorRepositoryStub()
        let model = AuthorViewModel(authorID: UUID(), repository: repository)
        await model.load()
        XCTAssertEqual(model.author?.displayName, "Автор")
        XCTAssertEqual(model.works.map(\.title), ["First"])
        await model.loadNextPage(after: try XCTUnwrap(model.works.last))
        XCTAssertNotNil(model.nextPageError)
        XCTAssertEqual(model.works.count, 1)
        await model.retryNextPage()
        XCTAssertNil(model.nextPageError)
        XCTAssertEqual(model.works.map(\.title), ["First", "Second"])
        model.readableOnly = true
        await model.load()
        XCTAssertEqual(model.works.map(\.title), ["Second"])
        XCTAssertEqual(model.totalCount, 1)
        let calls = await repository.requestedPages
        XCTAssertEqual(calls, [1, 2, 2, 1])
    }
}

private actor AuthorRepositoryStub: CatalogRepository {
    private(set) var requestedPages: [Int] = []
    private var failNextPage = true
    func author(id: UUID) async throws -> AuthorSummary {
        try JSONDecoder().decode(AuthorSummary.self, from: Data("{\"id\":\"\(id)\",\"display_name\":\"Автор\"}".utf8))
    }
    func works(authorID: UUID, page: Int, readableOnly: Bool) async throws -> PaginatedResponse<WorkSummary> {
        requestedPages.append(page)
        if page == 2 && failNextPage {
            failNextPage = false
            throw APIError.invalidResponse
        }
        let first = #"{"id":"11111111-1111-1111-1111-111111111111","slug":"first","title":"First","editions_count":0}"#
        let second = #"{"id":"22222222-2222-2222-2222-222222222222","slug":"second","title":"Second","editions_count":1}"#
        let results = readableOnly ? second : (page == 1 ? first : first + "," + second)
        let next = !readableOnly && page == 1 ? #""https://berynda.org/api/v1/works/?page=2""# : "null"
        let json = "{\"count\":\(readableOnly ? 1 : 2),\"next\":\(next),\"previous\":null,\"results\":[\(results)]}"
        return try JSONDecoder().decode(PaginatedResponse<WorkSummary>.self, from: Data(json.utf8))
    }
    func works(search: String?, page: Int) async throws -> PaginatedResponse<WorkSummary> { throw APIError.invalidResponse }
    func work(identifier: String) async throws -> WorkSummary { throw APIError.invalidResponse }
    func editions(workID: UUID) async throws -> [EditionSummary] { [] }
}
