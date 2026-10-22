import XCTest
@testable import BeryndaCore

final class WorkFiltersTests: XCTestCase {
    func testReadableSwitchIsNotASheetRefinement() {
        var filters = WorkFilters(readableOnly: true)
        XCTAssertFalse(filters.hasRefinements)
        XCTAssertFalse(filters.isUnfiltered)

        filters.language = "uk"
        filters.yearFrom = 1900
        filters.yearTo = 1950
        XCTAssertEqual(filters.refinementCount, 2, "A year range counts once")

        let cleared = filters.clearingRefinements()
        XCTAssertEqual(cleared, WorkFilters(readableOnly: true))
    }

    func testBackwardsYearRangeIsNormalised() {
        let filters = WorkFilters(yearFrom: 1950, yearTo: 1900)
        XCTAssertEqual(filters.normalizedYears.from, 1900)
        XCTAssertEqual(filters.normalizedYears.to, 1950)
    }

    func testFacetsDecodeTheServerShapeAndSkipBlankOptions() throws {
        let json = #"""
        {
          "total": 108762,
          "with_text": 82192,
          "decades": [{"decade": 1010, "count": 2}, {"decade": 2020, "count": 9}],
          "topics": [{"topic": "historical", "count": 11787}],
          "work_types": [{"work_type": "book", "count": 50195}, {"work_type": "", "count": 3}],
          "genres": [{"slug": "essay", "label": "Есе", "count": 281}],
          "languages": [{"language": "uk", "count": 103239}, {"language": null, "count": 1}]
        }
        """#
        let facets = try JSONDecoder().decode(WorkFacets.self, from: Data(json.utf8))

        XCTAssertEqual(facets.total, 108_762)
        XCTAssertEqual(facets.languages, [FacetOption(value: "uk", count: 103_239)])
        XCTAssertEqual(facets.workTypes, [FacetOption(value: "book", count: 50_195)])
        XCTAssertEqual(facets.yearBounds, 1010...2029)
    }

    func testFacetsWithoutGroupsDecodeEmpty() throws {
        let facets = try JSONDecoder().decode(WorkFacets.self, from: Data(#"{"total": 0}"#.utf8))
        XCTAssertTrue(facets.languages.isEmpty)
        XCTAssertTrue(facets.workTypes.isEmpty)
        XCTAssertNil(facets.yearBounds)
    }

    func testTopicDecodesChildrenAndRootness() throws {
        let json = #"""
        {
          "id": "49ad85b6-93d7-4efd-98c9-ae2015d1325f",
          "name": "Шкільні підручники",
          "name_en": null,
          "slug": "shkilni-pidruchnyky",
          "parent_slug": null,
          "work_count": 1074,
          "year_min": 2000,
          "year_max": 2025,
          "children": [
            {"id": "3b665f82-15da-4d26-b26e-379cb2a0d888", "name": "Інформатика", "name_en": null, "slug": "informatyka", "color": null},
            {"id": "not-a-uuid", "name": "Зламаний", "slug": "broken"}
          ]
        }
        """#
        let topic = try JSONDecoder().decode(TopicSummary.self, from: Data(json.utf8))

        XCTAssertTrue(topic.isRoot)
        XCTAssertEqual(topic.workCount, 1_074)
        XCTAssertEqual(topic.children.map(\.slug), ["informatyka"])
        XCTAssertEqual(topic.reference, TopicReference(slug: "shkilni-pidruchnyky", name: "Шкільні підручники"))
    }

    func testChildTopicIsNotARoot() throws {
        let json = #"{"id": "3b665f82-15da-4d26-b26e-379cb2a0d888", "name": "Інформатика", "slug": "informatyka", "parent_slug": "shkilni-pidruchnyky"}"#
        let topic = try JSONDecoder().decode(TopicSummary.self, from: Data(json.utf8))
        XCTAssertFalse(topic.isRoot)
        XCTAssertTrue(topic.children.isEmpty)
    }

    func testVocabularyNamesKnownCodesAndKeepsUnknownOnes() {
        XCTAssertEqual(CatalogVocabulary.languageName("uk"), "Українська")
        XCTAssertEqual(CatalogVocabulary.languageName("orv"), "Староукраїнська / руська")
        XCTAssertEqual(CatalogVocabulary.languageName("xx"), "XX")
        XCTAssertEqual(CatalogVocabulary.workTypeName("journal_issue"), "Номер журналу")
        XCTAssertEqual(CatalogVocabulary.workTypeName("new_kind"), "New kind")
    }
}
