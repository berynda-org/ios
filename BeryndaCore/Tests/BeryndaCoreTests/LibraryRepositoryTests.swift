import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import BeryndaCore

private actor LibraryTransportStub: HTTPTransport {
    private var responses: [(Int, Data)]
    private(set) var requests: [URLRequest] = []

    init(responses: [(Int, Data)]) {
        self.responses = responses
    }

    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let next = responses.removeFirst()
        return (
            next.1,
            HTTPURLResponse(
                url: request.url!,
                statusCode: next.0,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
        )
    }
}

final class LibraryRepositoryTests: XCTestCase {
    func testContinueReadingAndQuickAddMatchBackendContract() async throws {
        let continuePayload = Data(
            #"{"recently_read":[{"file_id":"44444444-4444-4444-4444-444444444444","edition_id":null,"work_id":null,"work_title":"Кобзар","edition_year":1840,"progress_percent":25,"position_value":"2","position_type":"page","last_read_at":"2026-09-03T12:00:00Z","cover_image_url":null}],"history_enabled":true}"#.utf8
        )
        let itemPayload = Data(
            #"{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","bibliography_list":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","work":"11111111-1111-1111-1111-111111111111","work_title":"Кобзар","work_slug":"kobzar","edition":null,"edition_year":null,"edition_title":null,"file":"44444444-4444-4444-4444-444444444444","position_type":"page","position_value":"2","page_number":2,"render_mode":null,"ordinal":1,"note":"","citation_override":"","citation":{},"created_at":"2026-09-03T12:00:00Z","updated_at":"2026-09-03T12:00:00Z"}"#.utf8
        )
        let transport = LibraryTransportStub(responses: [(200, continuePayload), (201, itemPayload)])
        let repository = LiveLibraryRepository(
            client: BeryndaAPIClient(
                baseURL: URL(string: "https://berynda.org/api/v1/")!,
                transport: transport
            )
        )

        let recent = try await repository.continueReading(limit: 999)
        let item = try await repository.quickAdd(
            workID: nil,
            fileID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            positionType: "page",
            positionValue: "2",
            pageNumber: 2
        )

        XCTAssertTrue(recent.historyEnabled)
        XCTAssertEqual(recent.recentlyRead.first?.workTitle, "Кобзар")
        XCTAssertEqual(item.pageNumber, 2)
        let requests = await transport.requests
        XCTAssertEqual(requests[0].url?.absoluteString, "https://berynda.org/api/v1/auth/me/reading/?limit=50")
        XCTAssertEqual(requests[1].httpMethod, "POST")
        let body = try XCTUnwrap(requests[1].httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["file"] as? String, "44444444-4444-4444-4444-444444444444")
        XCTAssertEqual(json["page_number"] as? Int, 2)
    }
}
