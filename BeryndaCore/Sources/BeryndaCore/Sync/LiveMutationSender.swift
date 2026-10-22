import Foundation

/// Sends queued writes to the API, each with the key it was queued with.
public struct LiveMutationSender: MutationSending {
    private let client: BeryndaAPIClient
    private let library: LiveLibraryRepository

    public init(client: BeryndaAPIClient) {
        self.client = client
        self.library = LiveLibraryRepository(client: client)
    }

    public func deliver(_ mutation: PendingMutation, idempotencyKey: String) async throws -> OutboxDelivery {
        switch mutation {
        case let .readingPosition(fileID, update, clientUpdatedAt):
            let response: PositionWriteResponse = try await client.request(
                .readingPosition(fileID: fileID),
                method: .put,
                body: update.stamped(clientUpdatedAt)
            )
            if response.applied == false, let stored = response.position {
                return .superseded(SupersededPosition(fileID: fileID, position: stored))
            }
            return .delivered
        case let .createList(title):
            _ = try await library.createList(title: title, idempotencyKey: idempotencyKey)
        case let .renameList(id, title):
            _ = try await library.renameList(id: id, title: title, idempotencyKey: idempotencyKey)
        case let .deleteList(id):
            do {
                try await library.deleteList(id: id, idempotencyKey: idempotencyKey)
            } catch APIError.notFound {
                // Already gone, which is what was asked for.
            }
        case let .addWork(listID, workID):
            _ = try await library.addWork(workID, toList: listID, idempotencyKey: idempotencyKey)
        case let .removeItem(listID, itemID):
            do {
                try await library.removeItem(listID: listID, itemID: itemID, idempotencyKey: idempotencyKey)
            } catch APIError.notFound {
            }
        case let .quickAdd(request):
            _ = try await library.quickAdd(request, idempotencyKey: idempotencyKey)
        }
        return .delivered
    }
}

/// `PUT files/{id}/reading-position/`: the stored position plus `applied`
/// (false when the server kept a newer position) and the older `recorded`
/// (false when the reader's history is off).
struct PositionWriteResponse: Decodable, Sendable {
    let applied: Bool?
    let recorded: Bool?
    let position: ReadingPosition?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applied = try? container.decodeIfPresent(Bool.self, forKey: .applied)
        recorded = try? container.decodeIfPresent(Bool.self, forKey: .recorded)
        position = try? ReadingPosition(from: decoder)
    }

    enum CodingKeys: String, CodingKey {
        case applied, recorded
    }
}
