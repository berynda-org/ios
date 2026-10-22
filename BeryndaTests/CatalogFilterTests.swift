import BeryndaCore
import XCTest
@testable import Berynda

@MainActor
final class CatalogFilterTests: XCTestCase {
    func testCatalogSendsEveryFilterWithTheSearch() async throws {
        let repository = FilterRecordingStub()
        let model = CatalogViewModel(repository: repository)
        model.query = "Кобзар"
        model.filters = WorkFilters(
            readableOnly: true,
            language: "uk",
            workType: "book",
            yearFrom: 1800,
            topic: TopicReference(slug: "poeziia", name: "Поезія")
        )

        await model.load()

        let requests = await repository.workRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.search, "Кобзар")
        XCTAssertEqual(requests.first?.filters, model.filters)
    }

    func testFacetsIgnoreTheSheetsOwnChoicesAndAreFetchedOncePerBase() async throws {
        let repository = FilterRecordingStub()
        let model = CatalogViewModel(repository: repository)
        let topic = TopicReference(slug: "poeziia", name: "Поезія")
        model.filters = WorkFilters(readableOnly: true, language: "uk", yearTo: 1900, topic: topic)

        await model.loadFacetsIfNeeded()
        // Changing a sheet choice keeps the same option base.
        model.filters.language = "ru"
        await model.loadFacetsIfNeeded()

        var requests = await repository.facetRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first, WorkFilters(readableOnly: true, topic: topic))
        XCTAssertEqual(model.facets?.languages.first?.value, "uk")

        model.filters.readableOnly = false
        await model.loadFacetsIfNeeded()
        requests = await repository.facetRequests
        XCTAssertEqual(requests.count, 2)
    }

    func testClearingRefinementsKeepsTheReadableSwitch() {
        let model = CatalogViewModel(repository: FilterRecordingStub())
        model.filters = WorkFilters(readableOnly: true, language: "uk", workType: "book")

        model.clearRefinements()

        XCTAssertEqual(model.filters, WorkFilters(readableOnly: true))
    }

    func testSearchOffersAuthorsAndPeriodicals() async throws {
        let repository = FilterRecordingStub()
        let model = CatalogViewModel(repository: repository)

        model.query = "Ш"
        await model.load()
        XCTAssertTrue(model.authorHits.isEmpty)

        model.query = " Шевченко "
        await model.load()
        // The lookup runs beside the works request; wait for it to land.
        for _ in 0..<50 where model.authorHits.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.authorHits.map(\.label), ["Тарас Шевченко"])
        XCTAssertEqual(model.periodicalHits.map(\.label), ["Шевченківський вісник"])

        // A filter change does not repeat a lookup for the same words.
        model.filters.readableOnly = true
        await model.load()
        let lookups = await repository.crossSearchQueries
        XCTAssertEqual(lookups, ["Шевченко"])
    }

    func testTopicPageListsItsWorksUnderTheReadableSwitch() async throws {
        let repository = FilterRecordingStub()
        let reference = TopicReference(slug: "poeziia", name: "Поезія")
        let model = TopicViewModel(reference: reference, readableOnly: true, repository: repository)

        await model.load()

        // The stub has no topic record; the page still stands on its works.
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.title, "Поезія")
        let requests = await repository.workRequests
        XCTAssertEqual(requests.map(\.filters), [WorkFilters(readableOnly: true, topic: reference)])
        XCTAssertNil(requests.first?.search ?? nil)
    }

    func testUkrainianPluralAgreement() {
        let forms = [1, 2, 5, 11, 21, 22, 112].map {
            UkrainianPlural.form($0, one: "твір", few: "твори", many: "творів")
        }
        XCTAssertEqual(forms, ["твір", "твори", "творів", "творів", "твір", "твори", "творів"])
    }

    func testTopicRootsSurviveAServerThatIgnoresTheParentFilter() async throws {
        let repository = FilterRecordingStub()
        let model = TopicListViewModel(repository: repository)

        await model.load()

        // Page 1 holds only subtopics and a topic without works, so the model
        // walks on to page 2 for something to show.
        XCTAssertEqual(model.topics.map(\.slug), ["root-b"])
        let pages = await repository.topicPages
        XCTAssertEqual(pages, [1, 2])
    }
}

private actor FilterRecordingStub: CatalogRepository {
    struct WorkRequest: Sendable {
        let search: String?
        let filters: WorkFilters
    }

    private(set) var workRequests: [WorkRequest] = []
    private(set) var facetRequests: [WorkFilters] = []
    private(set) var topicPages: [Int] = []
    private(set) var crossSearchQueries: [String] = []

    func crossSearch(query: String, types: [String], limit: Int) async throws -> [CrossSearchHit] {
        crossSearchQueries.append(query)
        return [
            CrossSearchHit(entityType: "person", id: UUID(), label: "Тарас Шевченко", birthYear: 1814, deathYear: 1861),
            CrossSearchHit(entityType: "periodical", id: UUID(), label: "Шевченківський вісник"),
        ]
    }

    func works(search: String?, page: Int) async throws -> PaginatedResponse<WorkSummary> {
        try Self.decode(#"{"count":0,"next":null,"previous":null,"results":[]}"#)
    }

    func works(search: String?, page: Int, filters: WorkFilters) async throws -> PaginatedResponse<WorkSummary> {
        workRequests.append(WorkRequest(search: search, filters: filters))
        return try await works(search: search, page: page)
    }

    func facets(search: String?, filters: WorkFilters) async throws -> WorkFacets {
        facetRequests.append(filters)
        return try Self.decode(#"{"total":2,"languages":[{"language":"uk","count":2}],"work_types":[],"decades":[]}"#)
    }

    /// Ignores `parent`, as a server without the filter does.
    func topics(parent: String?, search: String?, page: Int) async throws -> PaginatedResponse<TopicSummary> {
        topicPages.append(page)
        switch page {
        case 1:
            return try Self.decode(#"""
            {"count":4,"next":"https://berynda.org/api/v1/topics/?page=2","previous":null,"results":[
              {"id":"11111111-0000-0000-0000-000000000001","name":"Дочірня","slug":"child","parent_slug":"root-b","work_count":4,"children":[]},
              {"id":"11111111-0000-0000-0000-000000000002","name":"Порожня","slug":"root-a","parent_slug":null,"work_count":0,"children":[]}
            ]}
            """#)
        default:
            return try Self.decode(#"""
            {"count":4,"next":null,"previous":null,"results":[
              {"id":"11111111-0000-0000-0000-000000000003","name":"Корінь","slug":"root-b","parent_slug":null,"work_count":4,"children":[]},
              {"id":"11111111-0000-0000-0000-000000000004","name":"Ще дочірня","slug":"child-2","parent_slug":"root-b","work_count":1,"children":[]}
            ]}
            """#)
        }
    }

    func work(identifier: String) async throws -> WorkSummary { throw APIError.invalidResponse }
    func editions(workID: UUID) async throws -> [EditionSummary] { [] }

    private static func decode<Value: Decodable>(_ json: String) throws -> Value {
        try JSONDecoder().decode(Value.self, from: Data(json.utf8))
    }
}
