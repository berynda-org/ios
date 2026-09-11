import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import BeryndaCore

/// Records what the client puts on the wire for list edits and answers each
/// request with the next canned reply.
private actor ListMutationTransportStub: HTTPTransport {
    struct Reply: Sendable {
        let status: Int
        let body: Data
        let contentType: String?
    }

    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(replies: [Reply]) {
        self.replies = replies
    }

    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let next = replies.removeFirst()
        var headers: [String: String] = [:]
        if let contentType = next.contentType {
            headers["Content-Type"] = contentType
        }
        return (
            next.body,
            HTTPURLResponse(
                url: request.url!,
                statusCode: next.status,
                httpVersion: nil,
                headerFields: headers
            )!
        )
    }
}

/// Renaming and deleting a bibliography list and removing an item, checked
/// at the transport: the request the backend receives, not a repository stub.
final class LibraryMutationContractTests: XCTestCase {
    private let baseURL = URL(string: "https://berynda.org/api/v1/")!
    // Hex letters on purpose: `uuidString` is upper-case, the API paths are not.
    private let listID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    private let itemID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

    func testListEndpointsUseLowercasedUUIDPaths() {
        XCTAssertEqual(
            APIEndpoint.bibliographyList(id: listID).url(relativeTo: baseURL)?.absoluteString,
            "https://berynda.org/api/v1/lists/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/"
        )
        XCTAssertEqual(
            APIEndpoint.bibliographyListItem(listID: listID, itemID: itemID)
                .url(relativeTo: baseURL)?.absoluteString,
            "https://berynda.org/api/v1/lists/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/items/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/"
        )
    }

    func testRenameSendsAPatchWithOnlyTheTrimmedTitleAndDecodesTheList() async throws {
        // The shape `BibliographyListSerializer` answers with, extra fields
        // included, as `GET lists/` returns it.
        let updated = Data(
            #"{"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","owner":"99999999-9999-9999-9999-999999999999","title":"Джерела до курсової","description":"","citation_style":"dstu_8302_2015","visibility":"private","is_pinned":false,"work_count":1,"items":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","bibliography_list":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","work":"11111111-1111-1111-1111-111111111111","work_title":"Кобзар","work_slug":"kobzar","edition":null,"edition_year":null,"edition_title":null,"file":null,"position_type":null,"position_value":null,"page_number":null,"render_mode":null,"ordinal":1,"note":"","citation_override":"","citation":{},"created_at":"2026-09-03T12:00:00Z","updated_at":"2026-09-03T12:00:00Z"}],"created_at":"2026-09-01T12:00:00Z","updated_at":"2026-09-11T12:00:00Z"}"#.utf8
        )
        let (repository, transport) = makeRepository(replying: [
            .init(status: 200, body: updated, contentType: "application/json"),
        ])

        let list = try await repository.renameList(id: listID, title: "  Джерела до курсової \n")

        XCTAssertEqual(list.id, listID)
        XCTAssertEqual(list.title, "Джерела до курсової")
        XCTAssertEqual(list.workCount, 1)
        XCTAssertEqual(list.items.map(\.id), [itemID])

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://berynda.org/api/v1/lists/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        // Only the title: the endpoint is a partial update, so any other
        // field sent along would overwrite what the reader set elsewhere.
        XCTAssertEqual(Set(json.keys), ["title"])
        XCTAssertEqual(json["title"] as? String, "Джерела до курсової")
    }

    func testDeletingAListSendsADeleteAndAcceptsAnEmpty204() async throws {
        let (repository, transport) = makeRepository(replying: [
            .init(status: 204, body: Data(), contentType: nil),
        ])

        try await repository.deleteList(id: listID)

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.httpMethod, "DELETE")
        XCTAssertEqual(
            requests.first?.url?.absoluteString,
            "https://berynda.org/api/v1/lists/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/"
        )
        XCTAssertNil(requests.first?.httpBody)
    }

    func testRemovingAnItemSendsADeleteToTheItemAndAcceptsAnEmpty204() async throws {
        let (repository, transport) = makeRepository(replying: [
            .init(status: 204, body: Data(), contentType: nil),
        ])

        try await repository.removeItem(listID: listID, itemID: itemID)

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.httpMethod, "DELETE")
        XCTAssertEqual(
            requests.first?.url?.absoluteString,
            "https://berynda.org/api/v1/lists/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/items/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/"
        )
        XCTAssertNil(requests.first?.httpBody)
    }

    func testRemovingAnItemFromAListTheReaderDoesNotOwnSurfacesNotFound() async throws {
        // The item endpoint is owner-only and answers 404, not 403, to anyone else.
        let (repository, _) = makeRepository(replying: [
            .init(status: 404, body: Data(#"{"detail":"Not found."}"#.utf8), contentType: "application/json"),
        ])

        do {
            try await repository.removeItem(listID: listID, itemID: itemID)
            XCTFail("A 404 must not be reported as a removal")
        } catch APIError.notFound {
            // Expected.
        }
    }

    private func makeRepository(
        replying replies: [ListMutationTransportStub.Reply]
    ) -> (LiveLibraryRepository, ListMutationTransportStub) {
        let transport = ListMutationTransportStub(replies: replies)
        let repository = LiveLibraryRepository(
            client: BeryndaAPIClient(baseURL: baseURL, transport: transport)
        )
        return (repository, transport)
    }
}
