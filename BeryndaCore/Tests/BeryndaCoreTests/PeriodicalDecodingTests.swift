import XCTest
@testable import BeryndaCore

final class PeriodicalDecodingTests: XCTestCase {
    func testPeriodicalDecodesTheListRow() throws {
        let json = #"""
        {"id": "86027f56-9852-43f5-ad24-fcbbe33c2734", "slug": "veselka", "name": "Веселка", "name_latin": null,
         "periodical_type": "journal", "publisher": null, "issn": null, "language": "uk",
         "additional_languages": [], "description": null, "founded_year": 1954, "ceased_year": null,
         "is_active": true, "publication_place": "Київ", "issues_count": 76, "works_count": 76}
        """#
        let periodical = try JSONDecoder().decode(PeriodicalSummary.self, from: Data(json.utf8))

        XCTAssertEqual(periodical.slug, "veselka")
        XCTAssertEqual(periodical.issuesCount, 76)
        XCTAssertEqual(periodical.yearsLabel, "з 1954")
        XCTAssertEqual(periodical.publicationPlace, "Київ")
    }

    func testYearsAndIssuesDecodeAndIssuesAreAlwaysNamed() throws {
        let years = try JSONDecoder().decode(
            [PeriodicalYear].self,
            from: Data(#"[{"year":1984,"issues_count":5,"works_count":4}]"#.utf8)
        )
        XCTAssertEqual(years, [PeriodicalYear(year: 1984, issuesCount: 5, worksCount: 4)])

        let json = #"""
        [{"id": "42856f82-6ce9-416d-9b12-232053e4d3d5", "periodical": "86027f56-9852-43f5-ad24-fcbbe33c2734",
          "volume": null, "issue": "01 (348)", "year": 1984, "publication_date": null,
          "title": "1984, №01 (348)", "doi": null, "page_count": null, "cover_image_url": null},
         {"id": "42856f82-6ce9-416d-9b12-232053e4d3d6", "periodical": "86027f56-9852-43f5-ad24-fcbbe33c2734",
          "volume": "2", "issue": 3, "year": 1924, "title": "  "}]
        """#
        let issues = try JSONDecoder().decode([PeriodicalIssue].self, from: Data(json.utf8))

        XCTAssertEqual(issues.map(\.displayTitle), ["1984, №01 (348)", "Т. 2, № 3 (1924)"])
        XCTAssertEqual(issues[1].issue, "3", "A numeric issue is read as text")
    }

    func testIssueWorkCarriesItsPagesInTheIssue() throws {
        let json = #"""
        {"id": "e5617dec-230b-4240-9517-66ac6867f417", "slug": "veselka-1984-1", "title": "1984, №01 (348)",
         "authors": [], "editions_count": 1, "has_text_file": true, "issue_pages": "3–17"}
        """#
        let entry = try JSONDecoder().decode(PeriodicalIssueWork.self, from: Data(json.utf8))
        XCTAssertEqual(entry.work.title, "1984, №01 (348)")
        XCTAssertEqual(entry.issuePages, "3–17")
        XCTAssertEqual(entry.id, entry.work.id)
    }

    func testWorkLinkNamesItsPeriodical() throws {
        let json = #"""
        [{"id": "38d4b61f-da47-4396-9c3d-ab966bb13dce", "work": "e5617dec-230b-4240-9517-66ac6867f417",
          "periodical_issue": {"id": "42856f82-6ce9-416d-9b12-232053e4d3d5",
            "periodical": "86027f56-9852-43f5-ad24-fcbbe33c2734", "periodical_name": "Веселка",
            "periodical_slug": "veselka", "volume": null, "issue": "01 (348)", "year": 1984,
            "publication_date": null, "title": "1984, №01 (348)"},
          "pages": "", "article_number": null, "column_name": "Поезія", "doi": null}]
        """#
        let links = try JSONDecoder().decode([WorkPeriodicalLink].self, from: Data(json.utf8))
        let link = try XCTUnwrap(links.first)
        XCTAssertEqual(link.issue.periodicalName, "Веселка")
        XCTAssertEqual(link.issue.periodicalSlug, "veselka")
        XCTAssertNil(link.pages, "A blank page range is no page range")
        XCTAssertEqual(link.columnName, "Поезія")
    }
}
