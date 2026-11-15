import Foundation
import XCTest
@testable import BeryndaCore

final class JournalFoldingTests: XCTestCase {
    let base = URL(string: "https://berynda.org/api/v1/")!
    let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    func testCatalogAndFacetsFoldIssuesButIssuePagesStayAccessible() throws {
        let filters = WorkFilters(readableOnly: true, language: "uk").foldingJournalIssues
        for endpoint in [APIEndpoint.worksFiltered(search: "Визвольний шлях", page: 2, filters: filters),
                         .workFacets(search: "Визвольний шлях", filters: filters)] {
            let items = try query(endpoint)
            XCTAssertEqual(items["fold_journal_issues"], "true")
            XCTAssertEqual(items["mobile_readable"], "true")
            XCTAssertEqual(items["language"], "uk")
        }
        XCTAssertNil(try query(.periodicalIssueWorks(issueID: id, page: 2, readableOnly: false))["fold_journal_issues"])
        XCTAssertNil(try query(.authorWorks(id: id, page: 1, readableOnly: false))["fold_journal_issues"])
        XCTAssertTrue(filters.clearingRefinements().foldJournalIssues)
        XCTAssertFalse(filters.clearingRefinements().hasRefinements)
    }

    private func query(_ endpoint: APIEndpoint) throws -> [String: String] {
        let url = try XCTUnwrap(endpoint.url(relativeTo: base))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
}
