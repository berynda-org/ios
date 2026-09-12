import Foundation
import XCTest
@testable import BeryndaCore

final class WorkRightsClaimTests: XCTestCase {
    func testImportedPublicDomainTagNeedsConfirmedAssessment() throws {
        for status in [nil, "unknown", "likely", "unlikely", "unreviewed"] as [String?] {
            let work = try decode(summary: "public_domain", status: status)
            XCTAssertNil(work.rightsClaim, "Must withhold unsupported claim for \(status ?? "missing")")
        }
        XCTAssertEqual(try decode(summary: "public_domain", status: "confirmed").rightsClaim, .publicDomain)
    }

    func testDetailFixtureDoesNotTurnAnUnknownAssessmentIntoPublicDomain() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "work-detail", withExtension: "json"))
        let work = try JSONDecoder().decode(WorkSummary.self, from: Data(contentsOf: url))
        XCTAssertEqual(work.rightsSummary, "public_domain")
        XCTAssertEqual(work.pdStatus, "unknown")
        XCTAssertNil(work.rightsClaim)
    }

    func testExplicitPermissionsUseServerRegimeNamesIndependentlyOfPublicDomain() throws {
        for claim in [WorkRightsClaim.openLicense, .byPermission, .selfPublished] {
            XCTAssertEqual(try decode(summary: claim.rawValue, status: "unknown").rightsClaim, claim)
        }
    }

    func testUnclearOrUnsupportedRegimesDoNotCreateRightsClaims() throws {
        for summary in [nil, "none", "mixed", "external_link", "future_regime"] as [String?] {
            XCTAssertNil(try decode(summary: summary, status: "confirmed").rightsClaim)
        }
    }

    private func decode(summary: String?, status: String?) throws -> WorkSummary {
        var payload: [String: Any] = [
            "id": "11111111-1111-1111-1111-111111111111",
            "slug": "catalog-work", "title": "Catalog work"
        ]
        if let summary { payload["rights_summary"] = summary }
        if let status { payload["pd_status"] = status }
        return try JSONDecoder().decode(WorkSummary.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}
