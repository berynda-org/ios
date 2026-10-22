import Foundation
import XCTest
@testable import BeryndaCore

final class WorkDetailDecodingTests: XCTestCase {
    func testDecodesDetailOnlyBibliographyFields() throws {
        let work = try detail()

        XCTAssertEqual(work.originalTitle, "Лїсова пісня")
        XCTAssertEqual(work.abstract, "Драма-феєрія про Мавку та Лукаша.")
        XCTAssertEqual(work.literaryForm?.name, "Драма")
        XCTAssertEqual(work.additionalLanguages, ["pl"])
        XCTAssertEqual(work.topics.map { $0.name }, ["Українська література"])
        XCTAssertEqual(work.topics.map { $0.slug }, ["ukrainska-literatura"])
        XCTAssertEqual(work.genres.compactMap { $0.slug }, [], "Genres carry no slug in this fixture")
        XCTAssertFalse(work.isCollection)
        XCTAssertEqual(work.form, "verse")
        XCTAssertTrue(work.isDetailed)
    }

    func testFallsBackToTheEnglishTermNameWhenUkrainianIsMissing() throws {
        let work = try detail()
        XCTAssertEqual(work.genres.map { $0.name }, ["Феєрія", "Verse drama"])
    }

    func testKeepsContributorRolesInsteadOfFlatteningThem() throws {
        let work = try detail()

        XCTAssertEqual(work.contributors.count, 4)
        let grouped = work.contributorsByRole
        XCTAssertEqual(grouped.map { $0.role }, ["author", "translator", "editor"])
        XCTAssertEqual(grouped.first { $0.role == "author" }?.names, ["Леся Українка"])
        XCTAssertEqual(grouped.first { $0.role == "translator" }?.names, ["Jerzy Litwiniuk"])
        // A display-name override wins over the person's canonical name.
        XCTAssertEqual(grouped.first { $0.role == "editor" }?.names, ["І. Редактор"])
    }

    func testUnknownRolesAreCarriedButNotPresented() throws {
        let work = try detail()

        XCTAssertTrue(work.contributors.contains { $0.role == "dedicatee" })
        // An unrecognised role must not surface as an unlabelled name.
        XCTAssertFalse(work.contributorsByRole.contains { $0.role == "dedicatee" })
        XCTAssertFalse(work.authors.contains { $0.displayName == "Невідомий адресат" })
    }

    func testAuthorsAreDerivedFromContributionsWhenTheListFieldIsAbsent() throws {
        let work = try detail()
        XCTAssertEqual(
            work.authors.map { $0.displayName },
            ["Леся Українка", "Jerzy Litwiniuk", "І. Редактор"]
        )
    }

    func testUntonedWorkGetsItsDeterministicCover() throws {
        let work = try detail()
        XCTAssertNil(work.coverTone)
        XCTAssertEqual(work.coverDesign.tone, .plum)
        XCTAssertEqual(work.coverDesign.variant, .plain)
        XCTAssertEqual(work.coverDesign.glyph, "Л")
    }

    func testListRowStillDecodesAndReportsItselfAsThin() throws {
        let data = try fixture("works-page")
        let page = try JSONDecoder().decode(PaginatedResponse<WorkSummary>.self, from: data)
        let work = try XCTUnwrap(page.results.first)

        XCTAssertFalse(work.isDetailed)
        XCTAssertTrue(work.contributors.isEmpty)
        XCTAssertTrue(work.genres.isEmpty)
        XCTAssertNil(work.originalTitle)
        // The list row keeps working exactly as before.
        XCTAssertEqual(work.authors.map { $0.displayName }, ["Іван Котляревський"])
        XCTAssertEqual(work.coverDesign.tone, .oxblood)
        XCTAssertEqual(work.coverDesign.variant, .frame)
    }

    private func detail() throws -> WorkSummary {
        try JSONDecoder().decode(WorkSummary.self, from: try fixture("work-detail"))
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}
