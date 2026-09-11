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

    public func createList(title: String) async throws -> BibliographyList {
        try await client.request(
            .bibliographyLists,
            method: .post,
            body: CreateListBody(title: title.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }

    public func renameList(id: UUID, title: String) async throws -> BibliographyList {
        try await client.request(
            .bibliographyList(id: id),
            method: .patch,
            // Only the title: the endpoint is a partial update, and resending
            // the other fields would overwrite changes made elsewhere.
            body: RenameListBody(title: title.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }

    public func deleteList(id: UUID) async throws {
        _ = try await client.send(.bibliographyList(id: id), method: .delete)
    }

    public func removeItem(listID: UUID, itemID: UUID) async throws {
        _ = try await client.send(
            .bibliographyListItem(listID: listID, itemID: itemID),
            method: .delete
        )
    }

    public func quickAdd(
        workID: UUID?,
        fileID: UUID?,
        positionType: String?,
        positionValue: String?,
        pageNumber: Int?
    ) async throws -> BibliographyItem {
        try await client.request(
            .bibliographyQuickAdd,
            method: .post,
            body: QuickAddBody(
                work: workID,
                file: fileID,
                positionType: positionType,
                positionValue: positionValue,
                pageNumber: pageNumber
            )
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
