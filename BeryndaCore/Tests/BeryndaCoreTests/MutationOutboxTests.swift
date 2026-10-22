import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import BeryndaCore

final class MutationOutboxTests: XCTestCase {
    private let owner = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
    private let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    func testOnlyTheLatestPositionPerFileIsKept() async {
        let outbox = MutationOutbox(fileURL: nil)
        await outbox.enqueue(position(page: 3), ownerID: owner)
        await outbox.enqueue(.deleteList(id: UUID()), ownerID: owner)
        await outbox.enqueue(position(page: 7), ownerID: owner)

        let entries = await outbox.entries()
        XCTAssertEqual(entries.count, 2)
        guard case let .readingPosition(_, update, _) = entries.last?.mutation else {
            return XCTFail("The newest position must be queued last")
        }
        XCTAssertEqual(update.positionValue, "7")
    }

    func testFlushSendsInOrderWithTheKeyFromQueueing() async {
        let outbox = MutationOutbox(fileURL: nil)
        await outbox.enqueue(.createList(title: "Літо"), ownerID: owner, idempotencyKey: "key-1")
        await outbox.enqueue(.renameList(id: UUID(), title: "Осінь"), ownerID: owner, idempotencyKey: "key-2")
        let sender = RecordingSender()

        let report = await outbox.flush(ownerID: owner, sender: sender)

        XCTAssertEqual(report.delivered, 2)
        XCTAssertEqual(report.remaining, 0)
        let keys = await sender.keys
        XCTAssertEqual(keys, ["key-1", "key-2"])
    }

    func testAnotherAccountsWritesAreDroppedNotSent() async {
        let outbox = MutationOutbox(fileURL: nil)
        await outbox.enqueue(.deleteList(id: UUID()), ownerID: UUID())
        let sender = RecordingSender()

        let report = await outbox.flush(ownerID: owner, sender: sender)

        XCTAssertEqual(report.dropped, 1)
        let keys = await sender.keys
        XCTAssertTrue(keys.isEmpty)
        let entries = await outbox.entries()
        XCTAssertTrue(entries.isEmpty)
    }

    func testATransientFailureKeepsTheRestAndRetriesWithTheSameKey() async {
        let outbox = MutationOutbox(fileURL: nil)
        await outbox.enqueue(.createList(title: "Літо"), ownerID: owner, idempotencyKey: "key-1")
        await outbox.enqueue(.createList(title: "Зима"), ownerID: owner, idempotencyKey: "key-2")
        let sender = RecordingSender(failures: [APIError.transport])

        var report = await outbox.flush(ownerID: owner, sender: sender)
        XCTAssertEqual(report.delivered, 0)
        XCTAssertEqual(report.remaining, 2)
        let pending = await outbox.entries()
        XCTAssertEqual(pending.first?.attempts, 1)

        report = await outbox.flush(ownerID: owner, sender: sender)
        XCTAssertEqual(report.delivered, 2)
        let keys = await sender.keys
        XCTAssertEqual(keys, ["key-1", "key-1", "key-2"])
    }

    func testARefusalDropsOnlyThatWrite() async {
        let outbox = MutationOutbox(fileURL: nil)
        await outbox.enqueue(.deleteList(id: UUID()), ownerID: owner)
        await outbox.enqueue(.createList(title: "Літо"), ownerID: owner)
        let sender = RecordingSender(failures: [APIError.forbidden(APIErrorContext())])

        let report = await outbox.flush(ownerID: owner, sender: sender)

        XCTAssertEqual(report.dropped, 1)
        XCTAssertEqual(report.delivered, 1)
    }

    func testASupersededPositionIsReportedForAdoption() async throws {
        let outbox = MutationOutbox(fileURL: nil)
        await outbox.enqueue(position(page: 3), ownerID: owner)
        let stored = try JSONDecoder().decode(
            ReadingPosition.self,
            from: Data(#"{"position_type":"page","position_value":"40","progress_percent":20,"total_pages":212,"last_read_at":"2026-10-22T10:05:00+00:00"}"#.utf8)
        )
        let sender = RecordingSender(delivery: .superseded(SupersededPosition(fileID: fileID, position: stored)))

        let report = await outbox.flush(ownerID: owner, sender: sender)

        XCTAssertEqual(report.superseded.first?.position.positionValue, "40")
    }

    func testTheQueueSurvivesARelaunchAndClearingRemovesIt() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("outbox.json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let first = MutationOutbox(fileURL: url)
        await first.enqueue(.createList(title: "Літо"), ownerID: owner, idempotencyKey: "key-1")

        let relaunched = MutationOutbox(fileURL: url)
        let entries = await relaunched.entries()
        XCTAssertEqual(entries.map(\.idempotencyKey), ["key-1"])
        XCTAssertEqual(entries.first?.ownerID, owner)

        await relaunched.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testIdempotencyKeysFollowTheServerRule() {
        XCTAssertTrue(IdempotencyKey.isValid(IdempotencyKey.make()))
        XCTAssertFalse(IdempotencyKey.isValid(""))
        XCTAssertFalse(IdempotencyKey.isValid("has space"))
        XCTAssertFalse(IdempotencyKey.isValid(String(repeating: "a", count: 129)))
        XCTAssertFalse(IdempotencyKey.isValid("ключ"))
    }

    func testQueuedPositionIsSentWithItsTimeAndAdoptsANewerOne() async throws {
        let transport = OutboxTransport([
            (200, #"{"position_type":"page","position_value":"40","progress_percent":20,"total_pages":212,"last_read_at":"2026-10-22T10:05:00+00:00","applied":false}"#),
        ])
        let client = BeryndaAPIClient(baseURL: URL(string: "https://berynda.org/api/v1/")!, transport: transport)
        let sender = LiveMutationSender(client: client)
        let moment = Date(timeIntervalSince1970: 1_792_000_000)

        let delivery = try await sender.deliver(
            .readingPosition(
                fileID: fileID,
                update: ReadingPositionUpdate(positionType: "page", positionValue: "3", progressPercent: 1, totalPages: 212),
                clientUpdatedAt: moment
            ),
            idempotencyKey: "unused"
        )

        guard case let .superseded(superseded) = delivery else { return XCTFail("Expected the stored position") }
        XCTAssertEqual(superseded.position.positionValue, "40")
        let recorded = await transport.requests
        let request = try XCTUnwrap(recorded.first)
        XCTAssertEqual(request.method, "PUT")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any])
        XCTAssertEqual(body["client_updated_at"] as? String, ReadingPositionUpdate.timestamp(moment))
    }

    func testListMutationsCarryTheQueuedKey() async throws {
        let listID = UUID()
        let transport = OutboxTransport([(204, "")])
        let client = BeryndaAPIClient(baseURL: URL(string: "https://berynda.org/api/v1/")!, transport: transport)

        _ = try await LiveMutationSender(client: client).deliver(.deleteList(id: listID), idempotencyKey: "queued-key")

        let recorded = await transport.requests
        let request = try XCTUnwrap(recorded.first)
        XCTAssertEqual(request.method, "DELETE")
        XCTAssertEqual(request.headers[IdempotencyKey.headerName], "queued-key")
    }

    func testAKeyedPostIsRetriedAfterAServerError() async throws {
        let transport = OutboxTransport([
            (503, #"{"error":{"code":"UNAVAILABLE"}}"#),
            (201, #"{"id":"aaaaaaaa-1111-1111-1111-111111111111","title":"Літо","description":"","is_public":false,"items":[]}"#),
        ])
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport,
            sleeper: { _ in }
        )

        _ = try? await LiveLibraryRepository(client: client).createList(title: "Літо", idempotencyKey: "same-key")

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0.headers[IdempotencyKey.headerName] }, ["same-key", "same-key"])
    }

    private func position(page: Int) -> PendingMutation {
        .readingPosition(
            fileID: fileID,
            update: ReadingPositionUpdate(positionType: "page", positionValue: String(page), progressPercent: nil, totalPages: nil),
            clientUpdatedAt: Date()
        )
    }
}

private actor RecordingSender: MutationSending {
    private(set) var keys: [String] = []
    private var failures: [Error]
    private let delivery: OutboxDelivery

    init(failures: [Error] = [], delivery: OutboxDelivery = .delivered) {
        self.failures = failures
        self.delivery = delivery
    }

    func deliver(_ mutation: PendingMutation, idempotencyKey: String) async throws -> OutboxDelivery {
        keys.append(idempotencyKey)
        if !failures.isEmpty { throw failures.removeFirst() }
        return delivery
    }
}

private struct OutboxRequest: Sendable {
    let method: String?
    let headers: [String: String]
    let body: Data?
}

private actor OutboxTransport: HTTPTransport {
    private var responses: [(Int, String)]
    private(set) var requests: [OutboxRequest] = []

    init(_ responses: [(Int, String)]) {
        self.responses = responses
    }

    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        requests.append(OutboxRequest(
            method: request.httpMethod,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody
        ))
        let (status, body) = responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(body.utf8), response)
    }
}
