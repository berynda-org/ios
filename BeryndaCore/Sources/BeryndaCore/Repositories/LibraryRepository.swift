import Foundation

public protocol LibraryRepository: Sendable {
    func continueReading(limit: Int) async throws -> ContinueReadingResponse
    func bibliographyLists() async throws -> [BibliographyList]
    func createList(title: String) async throws -> BibliographyList
    /// `PATCH lists/<id>/` with only the title; the response is the whole
    /// updated list.
    func renameList(id: UUID, title: String) async throws -> BibliographyList
    /// `DELETE lists/<id>/` — a hard delete, answered 204 with no body.
    func deleteList(id: UUID) async throws
    /// `DELETE lists/<list>/items/<item>/`, answered 204 with no body. The
    /// server renumbers the remaining items and recounts the list, so callers
    /// reload rather than patch their copy.
    func removeItem(listID: UUID, itemID: UUID) async throws
    /// `POST lists/<id>/items/` with the work only. Quick add, by contrast,
    /// always files into the server's default list.
    func addWork(_ workID: UUID, toList listID: UUID) async throws -> BibliographyItem
    func quickAdd(
        workID: UUID?,
        fileID: UUID?,
        positionType: String?,
        positionValue: String?,
        pageNumber: Int?
    ) async throws -> BibliographyItem
    func publicCollections() async throws -> [PublicCollectionSummary]
    func savedCollections() async throws -> [PublicCollectionSummary]
    func setCollectionSaved(slug: String, saved: Bool) async throws
}

public struct LiveLibraryRepository: LibraryRepository {
    private let client: BeryndaAPIClient

    public init(client: BeryndaAPIClient) {
        self.client = client
    }

    public func continueReading(limit: Int = 20) async throws -> ContinueReadingResponse {
        try await client.request(.continueReading(limit: limit))
    }

    public func bibliographyLists() async throws -> [BibliographyList] {
        try await client.request(.bibliographyLists)
    }

    // Every list mutation carries an idempotency key, so the client's own
    // retry after a lost response replays the first result instead of
    // writing twice. The keyed variants are what the outbox replays.

    public func createList(title: String) async throws -> BibliographyList {
        try await createList(title: title, idempotencyKey: IdempotencyKey.make())
    }

    public func createList(title: String, idempotencyKey: String) async throws -> BibliographyList {
        try await client.request(
            .bibliographyLists,
            method: .post,
            body: CreateListBody(title: title.trimmingCharacters(in: .whitespacesAndNewlines)),
            headers: IdempotencyKey.headers(idempotencyKey)
        )
    }

    public func renameList(id: UUID, title: String) async throws -> BibliographyList {
        try await renameList(id: id, title: title, idempotencyKey: IdempotencyKey.make())
    }

    public func renameList(id: UUID, title: String, idempotencyKey: String) async throws -> BibliographyList {
        try await client.request(
            .bibliographyList(id: id),
            method: .patch,
            // Only the title: the endpoint is a partial update, and resending
            // the other fields would overwrite changes made elsewhere.
            body: RenameListBody(title: title.trimmingCharacters(in: .whitespacesAndNewlines)),
            headers: IdempotencyKey.headers(idempotencyKey)
        )
    }

    public func deleteList(id: UUID) async throws {
        try await deleteList(id: id, idempotencyKey: IdempotencyKey.make())
    }

    public func deleteList(id: UUID, idempotencyKey: String) async throws {
        _ = try await client.send(
            .bibliographyList(id: id),
            method: .delete,
            headers: IdempotencyKey.headers(idempotencyKey)
        )
    }

    public func removeItem(listID: UUID, itemID: UUID) async throws {
        try await removeItem(listID: listID, itemID: itemID, idempotencyKey: IdempotencyKey.make())
    }

    public func removeItem(listID: UUID, itemID: UUID, idempotencyKey: String) async throws {
        _ = try await client.send(
            .bibliographyListItem(listID: listID, itemID: itemID),
            method: .delete,
            headers: IdempotencyKey.headers(idempotencyKey)
        )
    }

    public func addWork(_ workID: UUID, toList listID: UUID) async throws -> BibliographyItem {
        try await addWork(workID, toList: listID, idempotencyKey: IdempotencyKey.make())
    }

    public func addWork(_ workID: UUID, toList listID: UUID, idempotencyKey: String) async throws -> BibliographyItem {
        try await client.request(
            .bibliographyListItems(listID: listID),
            method: .post,
            body: AddWorkBody(work: workID),
            headers: IdempotencyKey.headers(idempotencyKey)
        )
    }

    public func quickAdd(
        workID: UUID?,
        fileID: UUID?,
        positionType: String?,
        positionValue: String?,
        pageNumber: Int?
    ) async throws -> BibliographyItem {
        try await quickAdd(
            QuickAddRequest(
                workID: workID,
                fileID: fileID,
                positionType: positionType,
                positionValue: positionValue,
                pageNumber: pageNumber
            ),
            idempotencyKey: IdempotencyKey.make()
        )
    }

    public func quickAdd(_ request: QuickAddRequest, idempotencyKey: String) async throws -> BibliographyItem {
        try await client.request(
            .bibliographyQuickAdd,
            method: .post,
            body: QuickAddBody(
                work: request.workID,
                file: request.fileID,
                positionType: request.positionType,
                positionValue: request.positionValue,
                pageNumber: request.pageNumber
            ),
            headers: IdempotencyKey.headers(idempotencyKey)
        )
    }

    public func publicCollections() async throws -> [PublicCollectionSummary] {
        try await client.request(.publicCollections)
    }

    public func savedCollections() async throws -> [PublicCollectionSummary] {
        try await client.request(.savedCollections)
    }

    public func setCollectionSaved(slug: String, saved: Bool) async throws {
        _ = try await client.send(.collectionSave(slug: slug), method: saved ? .post : .delete)
    }
}

private struct CreateListBody: Encodable, Sendable {
    let title: String
}

private struct AddWorkBody: Encodable, Sendable {
    let work: UUID
}

private struct RenameListBody: Encodable, Sendable {
    let title: String
}

private struct QuickAddBody: Encodable, Sendable {
    let work: UUID?
    let file: UUID?
    let positionType: String?
    let positionValue: String?
    let pageNumber: Int?

    enum CodingKeys: String, CodingKey {
        case work, file
        case positionType = "position_type"
        case positionValue = "position_value"
        case pageNumber = "page_number"
    }
}
