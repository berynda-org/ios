import Foundation
import XCTest
import BeryndaCore
@testable import Berynda

/// Writes made without a connection: queued for the signed-in account, sent
/// later, and a newer server position adopted instead of overwritten.
@MainActor
final class OfflineQueueTests: XCTestCase {
    private static let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    func testAListChangeMadeOfflineIsQueuedForTheAccount() async throws {
        let fixture = try await makeFixture()
        let library = LibraryViewModel(repository: UnreachableLibrary(), account: fixture.account, offline: fixture.offline)
        let listID = UUID()

        let result = await library.deleteList(id: listID)

        XCTAssertEqual(result, .queued)
        let entries = await fixture.outbox.entries()
        XCTAssertEqual(entries.map(\.mutation), [.deleteList(id: listID)])
        XCTAssertEqual(entries.first?.ownerID, fixture.account.profile?.id)
    }

    func testSignedOutChangesAreNotQueued() async throws {
        let fixture = try await makeFixture()
        await fixture.account.signOut()

        await fixture.offline.enqueue(.deleteList(id: UUID()), ownerID: fixture.account.profile?.id)

        let entries = await fixture.outbox.entries()
        XCTAssertTrue(entries.isEmpty)
    }

    func testSyncSendsTheQueueAndAdoptsANewerPosition() async throws {
        let stored = try JSONDecoder().decode(
            ReadingPosition.self,
            from: Data(#"{"position_type":"page","position_value":"40","progress_percent":20,"total_pages":212}"#.utf8)
        )
        let sender = SupersedingSender(position: SupersededPosition(fileID: Self.fileID, position: stored))
        let fixture = try await makeFixture(sender: sender)
        let owner = try XCTUnwrap(fixture.account.profile?.id)
        await fixture.outbox.enqueue(
            .readingPosition(
                fileID: Self.fileID,
                update: ReadingPositionUpdate(positionType: "page", positionValue: "3", progressPercent: 1, totalPages: 212),
                clientUpdatedAt: Date()
            ),
            ownerID: owner
        )

        await fixture.offline.sync(ownerID: owner)

        let remaining = await fixture.outbox.entries()
        XCTAssertTrue(remaining.isEmpty)
        let local = await fixture.positions.position(for: Self.fileID)
        XCTAssertEqual(local?.page, 40)
    }

    // MARK: - Fixtures

    private struct Fixture {
        let account: AccountViewModel
        let positions: LocalReadingPositionStore
        let outbox: MutationOutbox
        let offline: OfflineSync
    }

    private func makeFixture(sender: (any MutationSending)? = nil) async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineQueueTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let positions = LocalReadingPositionStore(
            directory: directory.appendingPathComponent("positions", isDirectory: true)
        )
        let recentlyViewed = RecentlyViewedStore(
            directory: directory.appendingPathComponent("recently-viewed", isDirectory: true)
        )
        let authentication = UITestAuthenticationService()
        let session = SessionController(tokenStore: UITestTokenStore(), authentication: authentication)
        let account = AccountViewModel(
            session: session,
            authentication: authentication,
            repository: UITestAccountRepository(),
            localPositions: positions,
            recentlyViewed: recentlyViewed
        )
        let signedIn = await account.signIn(email: "reader@example.org", password: "password123")
        XCTAssertTrue(signedIn)
        let outbox = MutationOutbox(fileURL: nil)
        let offline = OfflineSync(
            outbox: outbox,
            library: OfflineLibrary(directory: directory.appendingPathComponent("offline", isDirectory: true)),
            sender: sender,
            statusChecker: nil,
            source: UITestRepository(),
            localPositions: positions
        )
        return Fixture(account: account, positions: positions, outbox: outbox, offline: offline)
    }
}

private struct SupersedingSender: MutationSending {
    let position: SupersededPosition

    func deliver(_ mutation: PendingMutation, idempotencyKey: String) async throws -> OutboxDelivery {
        .superseded(position)
    }
}

/// Every list call fails as if the device had no connection.
private struct UnreachableLibrary: LibraryRepository {
    func continueReading(limit: Int) async throws -> ContinueReadingResponse { throw APIError.transport }
    func bibliographyLists() async throws -> [BibliographyList] { throw APIError.transport }
    func createList(title: String) async throws -> BibliographyList { throw APIError.transport }
    func renameList(id: UUID, title: String) async throws -> BibliographyList { throw APIError.transport }
    func deleteList(id: UUID) async throws { throw APIError.transport }
    func removeItem(listID: UUID, itemID: UUID) async throws { throw APIError.transport }
    func addWork(_ workID: UUID, toList listID: UUID) async throws -> BibliographyItem { throw APIError.transport }
    func quickAdd(
        workID: UUID?,
        fileID: UUID?,
        positionType: String?,
        positionValue: String?,
        pageNumber: Int?
    ) async throws -> BibliographyItem { throw APIError.transport }
    func publicCollections() async throws -> [PublicCollectionSummary] { [] }
    func savedCollections() async throws -> [PublicCollectionSummary] { [] }
    func setCollectionSaved(slug: String, saved: Bool) async throws { throw APIError.transport }
}
