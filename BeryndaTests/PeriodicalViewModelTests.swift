import BeryndaCore
import XCTest
@testable import Berynda

@MainActor
final class PeriodicalViewModelTests: XCTestCase {
    func testAYearsIssuesAreFetchedOnceAndKept() async throws {
        let repository = PeriodicalStub(years: [1925, 1924])
        let model = PeriodicalViewModel(identifier: "visnyk", name: "Вісник", repository: repository)

        await model.load()
        XCTAssertEqual(model.years.map(\.year), [1925, 1924])
        XCTAssertEqual(model.title, "Шевченківський вісник")
        XCTAssertTrue(model.expandedYears.isEmpty, "Several years start closed")

        await model.toggle(1925)
        XCTAssertTrue(model.expandedYears.contains(1925))
        guard case let .loaded(issues) = model.issuesByYear[1925] else {
            return XCTFail("Expected the 1925 issues")
        }
        XCTAssertEqual(issues.map(\.displayTitle), ["1925, № 1"])

        await model.toggle(1925)
        await model.toggle(1925)
        let requested = await repository.issueYears
        XCTAssertEqual(requested, [1925], "Closing and reopening a year reuses its issues")
    }

    func testASingleYearOpensByItself() async throws {
        let model = PeriodicalViewModel(identifier: "visnyk", name: "Вісник", repository: PeriodicalStub(years: [1925]))

        await model.load()

        XCTAssertEqual(model.expandedYears, [1925])
    }

    func testAMissingRecordStillShowsTheYears() async throws {
        let model = PeriodicalViewModel(
            identifier: "visnyk",
            name: "Вісник",
            repository: PeriodicalStub(years: [1925], recordFails: true)
        )

        await model.load()

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.title, "Вісник")
        XCTAssertEqual(model.years.count, 1)
    }

    func testIssuePageSendsTheReadableSwitch() async throws {
        let repository = PeriodicalStub(years: [])
        let issueID = UUID()
        let model = PeriodicalIssueViewModel(issueID: issueID, readableOnly: true, repository: repository)

        await model.load()

        XCTAssertEqual(model.works.first?.issuePages, "3–17")
        XCTAssertEqual(model.totalCount, 1)
        let requests = await repository.issueWorkRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.0, issueID)
        XCTAssertEqual(requests.first?.1, true)
    }
}

private actor PeriodicalStub: CatalogRepository {
    let yearValues: [Int]
    let recordFails: Bool
    private(set) var issueYears: [Int] = []
    private(set) var issueWorkRequests: [(UUID, Bool)] = []

    init(years: [Int], recordFails: Bool = false) {
        yearValues = years
        self.recordFails = recordFails
    }

    func periodical(identifier: String) async throws -> PeriodicalSummary {
        if recordFails { throw APIError.invalidResponse }
        return try Self.decode(#"{"id":"99999999-0000-0000-0000-000000000001","slug":"visnyk","name":"Шевченківський вісник","issues_count":1,"works_count":1}"#)
    }

    func periodicalYears(identifier: String) async throws -> [PeriodicalYear] {
        yearValues.map { PeriodicalYear(year: $0, issuesCount: 1, worksCount: 1) }
    }

    func periodicalIssues(identifier: String, year: Int) async throws -> [PeriodicalIssue] {
        issueYears.append(year)
        return try Self.decode(#"[{"id":"77777777-1925-0000-0000-000000000001","issue":"1","year":1925,"title":"1925, № 1"}]"#)
    }

    func works(issueID: UUID, page: Int, readableOnly: Bool) async throws -> PaginatedResponse<PeriodicalIssueWork> {
        issueWorkRequests.append((issueID, readableOnly))
        return try Self.decode(#"{"count":1,"next":null,"previous":null,"results":[{"id":"11111111-1111-1111-1111-111111111111","slug":"kobzar","title":"Кобзар","editions_count":1,"issue_pages":"3–17"}]}"#)
    }

    func works(search: String?, page: Int) async throws -> PaginatedResponse<WorkSummary> {
        try Self.decode(#"{"count":0,"next":null,"previous":null,"results":[]}"#)
    }

    func work(identifier: String) async throws -> WorkSummary { throw APIError.invalidResponse }
    func editions(workID: UUID) async throws -> [EditionSummary] { [] }

    private static func decode<Value: Decodable>(_ json: String) throws -> Value {
        try JSONDecoder().decode(Value.self, from: Data(json.utf8))
    }
}
