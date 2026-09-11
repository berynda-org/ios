import Foundation
import XCTest
import BeryndaCore
@testable import Berynda

/// Renaming and deleting bibliography lists and taking an item back out,
/// through the library model — plus the model's refusal to run two
/// mutations at once.
@MainActor
final class LibraryListEditingTests: XCTestCase {
    private let listID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    private let otherListID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
    private let itemID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    private let otherItemID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
    private let kobzarID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let forestSongID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    func testRenamingSendsTheTrimmedTitleOnceAndTheReloadShowsIt() async throws {
        let repository = ListEditingRepositoryStub(lists: [
            ListFixture(id: listID, title: "Курсова", items: []),
        ])
        let model = await makeLibraryModel(repository: repository)
        await model.load()

        let result = await model.renameList(id: listID, title: "  Джерела до курсової \n")

        XCTAssertEqual(result, .saved)
        let calls = await repository.renameCalls
        XCTAssertEqual(calls, [RenameCall(id: listID, title: "Джерела до курсової")])
        XCTAssertEqual(loadedLists(model)?.map(\.title), ["Джерела до курсової"])
        XCTAssertFalse(model.isMutating)
    }

    func testABlankOrOverlongTitleIsRejectedWithoutANetworkCall() async throws {
        let repository = ListEditingRepositoryStub(lists: [
            ListFixture(id: listID, title: "Курсова", items: []),
        ])
        let model = await makeLibraryModel(repository: repository)
        await model.load()

        let rejected = [
            "",
            "  \n\t ",
            String(repeating: "я", count: 256),
            // 60 characters to Swift but 300 code points, which is what the
            // server's max_length counts.
            String(repeating: "👨‍👩‍👧", count: 60),
        ]
        for title in rejected {
            let result = await model.renameList(id: listID, title: title)
            if case .failed = result {} else {
                XCTFail("A title of \(title.unicodeScalars.count) code points must be refused, got \(result)")
            }
        }

        let calls = await repository.renameCalls
        XCTAssertTrue(calls.isEmpty, "An invalid title must not reach the network")
        XCTAssertEqual(loadedLists(model)?.map(\.title), ["Курсова"])
        XCTAssertFalse(model.isMutating)

        // The limit itself is allowed.
        let longest = String(repeating: "я", count: 255)
        let accepted = await model.renameList(id: listID, title: longest)
        XCTAssertEqual(accepted, .saved)
        let afterLongest = await repository.renameCalls
        XCTAssertEqual(afterLongest.map(\.title), [longest])
    }

    func testDeletingAListIssuesOneCallAndTheReloadDropsIt() async throws {
        let repository = ListEditingRepositoryStub(lists: [
            ListFixture(id: listID, title: "Курсова", items: [ItemFixture(id: itemID, work: kobzarID)]),
            ListFixture(id: otherListID, title: "Дипломна", items: []),
        ])
        let model = await makeLibraryModel(repository: repository)
        await model.load()

        let result = await model.deleteList(id: listID)

        XCTAssertEqual(result, .removed)
        let calls = await repository.deleteCalls
        XCTAssertEqual(calls, [listID])
        XCTAssertEqual(loadedLists(model)?.map(\.id), [otherListID])
        XCTAssertFalse(model.isMutating)
    }

    func testRemovingAnItemTargetsThatListAndItemAndTheReloadRecountsIt() async throws {
        let repository = ListEditingRepositoryStub(lists: [
            ListFixture(id: listID, title: "Курсова", items: [
                ItemFixture(id: itemID, work: kobzarID),
                ItemFixture(id: otherItemID, work: forestSongID),
            ]),
            ListFixture(id: otherListID, title: "Дипломна", items: []),
        ])
        let model = await makeLibraryModel(repository: repository)
        await model.load()

        let result = await model.removeItem(listID: listID, itemID: otherItemID)

        XCTAssertEqual(result, .removed)
        let calls = await repository.removeCalls
        XCTAssertEqual(calls, [RemoveCall(listID: listID, itemID: otherItemID)])
        let list = loadedLists(model)?.first { $0.id == listID }
        XCTAssertEqual(list?.items.map(\.id), [itemID])
        XCTAssertEqual(list?.workCount, 1)
        XCTAssertFalse(model.isMutating)
    }

    func testQuickAddingAWorkAlreadyInAListIsReportedWithoutANetworkCall() async throws {
        let repository = ListEditingRepositoryStub(lists: [
            ListFixture(id: listID, title: "Курсова", items: [
                ItemFixture(id: itemID, work: kobzarID),
                ItemFixture(id: otherItemID, work: forestSongID, file: fileID, pageNumber: 3),
            ]),
        ])
        let model = await makeLibraryModel(repository: repository)

        // No load(): quick add is offered on the work page before the Library
        // tab ever opens, so the model fetches the snapshot itself first.
        let work = await model.quickAdd(workID: kobzarID)
        let samePage = await model.quickAdd(fileID: fileID, page: 3)

        XCTAssertEqual(work, .alreadySaved)
        XCTAssertEqual(samePage, .alreadySaved)
        let calls = await repository.quickAddCalls
        XCTAssertTrue(calls.isEmpty, "A duplicate must not reach the network")
        XCTAssertFalse(model.isMutating)

        // Another page of the same file is a new bookmark, not a duplicate.
        let otherPage = await model.quickAdd(fileID: fileID, page: 4)
        XCTAssertEqual(otherPage, .saved)
        let afterOtherPage = await repository.quickAddCalls
        XCTAssertEqual(afterOtherPage, [QuickAddCall(workID: nil, fileID: fileID, pageNumber: 4)])
    }

    func testASecondMutationIsRefusedWhileTheFirstIsStillFetchingTheSnapshot() async throws {
        let repository = ListEditingRepositoryStub(lists: [
            ListFixture(id: listID, title: "Курсова", items: [ItemFixture(id: itemID, work: kobzarID)]),
        ])
        let model = await makeLibraryModel(repository: repository)
        let newWork = forestSongID

        // No load(), so the first quick add has to fetch the snapshot before
        // its duplicate check — and that fetch is held open, parking the
        // mutation inside the very await that used to come before the flag.
        await repository.holdNextListsFetch()
        let first = Task { await model.quickAdd(workID: newWork) }
        await repository.waitUntilListsFetchIsHeld()

        XCTAssertTrue(model.isMutating, "The first mutation must claim the model before it suspends")
        let rename = await model.renameList(id: listID, title: "Інша назва")
        let delete = await model.deleteList(id: listID)
        let remove = await model.removeItem(listID: listID, itemID: itemID)
        let add = await model.quickAdd(workID: newWork)
        XCTAssertEqual(rename, .inProgress)
        XCTAssertEqual(delete, .inProgress)
        XCTAssertEqual(remove, .inProgress)
        XCTAssertEqual(add, .inProgress)
        let renames = await repository.renameCalls
        let deletes = await repository.deleteCalls
        let removes = await repository.removeCalls
        let heldAdds = await repository.quickAddCalls
        XCTAssertTrue(renames.isEmpty)
        XCTAssertTrue(deletes.isEmpty)
        XCTAssertTrue(removes.isEmpty)
        XCTAssertTrue(heldAdds.isEmpty, "Nothing may reach the network while the first mutation is parked")

        await repository.releaseHeldListsFetch()
        let firstResult = await first.value

        XCTAssertEqual(firstResult, .saved)
        XCTAssertFalse(model.isMutating)
        let adds = await repository.quickAddCalls
        XCTAssertEqual(adds, [QuickAddCall(workID: newWork, fileID: nil, pageNumber: nil)])
    }

    // MARK: - Fixtures

    private func loadedLists(_ model: LibraryViewModel) -> [BibliographyList]? {
        guard case let .loaded(_, lists, _) = model.state else { return nil }
        return lists
    }

    /// A signed-in library model over `repository`, the way `AppEnvironment`
    /// wires one up. The library only serves an authenticated account, so
    /// the account signs in with the UI-test credentials first.
    private func makeLibraryModel(repository: any LibraryRepository) async -> LibraryViewModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryListEditingTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let authentication = UITestAuthenticationService()
        let session = SessionController(
            tokenStore: UITestTokenStore(),
            authentication: authentication
        )
        let account = AccountViewModel(
            session: session,
            authentication: authentication,
            repository: UITestAccountRepository(),
            localPositions: LocalReadingPositionStore(
                directory: directory.appendingPathComponent("positions", isDirectory: true)
            ),
            recentlyViewed: RecentlyViewedStore(
                directory: directory.appendingPathComponent("recently-viewed", isDirectory: true)
            )
        )
        let signedIn = await account.signIn(email: "reader@example.org", password: "password123")
        XCTAssertTrue(signedIn, "The UI-test account must sign in for the library to load")
        XCTAssertEqual(account.state, .authenticated)

        return LibraryViewModel(repository: repository, account: account)
    }
}

private struct ListFixture: Sendable {
    let id: UUID
    var title: String
    var items: [ItemFixture]
}

private struct ItemFixture: Sendable {
    let id: UUID
    let work: UUID
    var file: UUID? = nil
    var pageNumber: Int? = nil
}

private struct RenameCall: Equatable, Sendable {
    let id: UUID
    let title: String
}

private struct RemoveCall: Equatable, Sendable {
    let listID: UUID
    let itemID: UUID
}

private struct QuickAddCall: Equatable, Sendable {
    let workID: UUID?
    let fileID: UUID?
    let pageNumber: Int?
}

/// Decoded rather than constructed: the core models expose no memberwise
/// initializers. Serialised with JSONSerialization so any title is escaped.
private enum LibraryFixtures {
    static func list(_ fixture: ListFixture) throws -> BibliographyList {
        let object: [String: Any] = [
            "id": fixture.id.uuidString.lowercased(),
            "title": fixture.title,
            "description": "",
            "citation_style": "dstu_8302_2015",
            "visibility": "private",
            "is_pinned": false,
            // As the server keeps it: recounted on every change to the items.
            "work_count": fixture.items.count,
            "items": fixture.items.map { itemObject($0) },
        ]
        return try JSONDecoder().decode(
            BibliographyList.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    static func item(_ fixture: ItemFixture) throws -> BibliographyItem {
        try JSONDecoder().decode(
            BibliographyItem.self,
            from: JSONSerialization.data(withJSONObject: itemObject(fixture))
        )
    }

    private static func itemObject(_ fixture: ItemFixture) -> [String: Any] {
        var object: [String: Any] = [
            "id": fixture.id.uuidString.lowercased(),
            "work": fixture.work.uuidString.lowercased(),
            "work_title": "Твір",
            "note": "",
        ]
        if let file = fixture.file {
            object["file"] = file.uuidString.lowercased()
        }
        if let page = fixture.pageNumber {
            object["position_type"] = "page"
            object["position_value"] = String(page)
            object["page_number"] = page
        }
        return object
    }
}

/// A library that edits its own lists the way the server does and records
/// every mutation the model sends it. One `bibliographyLists()` call can be
/// held open on request, to park a mutation inside its snapshot fetch.
private actor ListEditingRepositoryStub: LibraryRepository {
    enum StubError: Error {
        case unsupported
        case missingList
    }

    private var lists: [ListFixture]
    private(set) var renameCalls: [RenameCall] = []
    private(set) var deleteCalls: [UUID] = []
    private(set) var removeCalls: [RemoveCall] = []
    private(set) var quickAddCalls: [QuickAddCall] = []

    private var holdsNextListsFetch = false
    private var heldListsFetch: CheckedContinuation<Void, Never>?
    private var heldFetchWaiters: [CheckedContinuation<Void, Never>] = []

    init(lists: [ListFixture]) {
        self.lists = lists
    }

    // MARK: Holding a fetch

    /// Parks the next `bibliographyLists()` until `releaseHeldListsFetch()`.
    /// Only that one call is held, so a regression lets the other calls
    /// through and fails the test instead of hanging it.
    func holdNextListsFetch() {
        holdsNextListsFetch = true
    }

    /// Returns once the held fetch has been entered and is parked.
    func waitUntilListsFetchIsHeld() async {
        if heldListsFetch != nil { return }
        await withCheckedContinuation { continuation in
            heldFetchWaiters.append(continuation)
        }
    }

    func releaseHeldListsFetch() {
        heldListsFetch?.resume()
        heldListsFetch = nil
    }

    // MARK: LibraryRepository

    func continueReading(limit: Int) async throws -> ContinueReadingResponse {
        ContinueReadingResponse(recentlyRead: [], historyEnabled: true)
    }

    func bibliographyLists() async throws -> [BibliographyList] {
        if holdsNextListsFetch {
            holdsNextListsFetch = false
            await withCheckedContinuation { continuation in
                heldListsFetch = continuation
                let waiters = heldFetchWaiters
                heldFetchWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }
        return try lists.map { try LibraryFixtures.list($0) }
    }

    func createList(title: String) async throws -> BibliographyList {
        throw StubError.unsupported
    }

    func renameList(id: UUID, title: String) async throws -> BibliographyList {
        renameCalls.append(RenameCall(id: id, title: title))
        guard let index = lists.firstIndex(where: { $0.id == id }) else {
            throw StubError.missingList
        }
        lists[index].title = title
        return try LibraryFixtures.list(lists[index])
    }

    func deleteList(id: UUID) async throws {
        deleteCalls.append(id)
        guard lists.contains(where: { $0.id == id }) else { throw StubError.missingList }
        lists.removeAll { $0.id == id }
    }

    func removeItem(listID: UUID, itemID: UUID) async throws {
        removeCalls.append(RemoveCall(listID: listID, itemID: itemID))
        guard let index = lists.firstIndex(where: { $0.id == listID }),
              lists[index].items.contains(where: { $0.id == itemID })
        else { throw StubError.missingList }
        lists[index].items.removeAll { $0.id == itemID }
    }

    func quickAdd(
        workID: UUID?,
        fileID: UUID?,
        positionType: String?,
        positionValue: String?,
        pageNumber: Int?
    ) async throws -> BibliographyItem {
        quickAddCalls.append(QuickAddCall(workID: workID, fileID: fileID, pageNumber: pageNumber))
        // The server fills in the work of a file-only bookmark.
        let item = ItemFixture(id: UUID(), work: workID ?? UUID(), file: fileID, pageNumber: pageNumber)
        if !lists.isEmpty { lists[0].items.append(item) }
        return try LibraryFixtures.item(item)
    }

    func publicCollections() async throws -> [PublicCollectionSummary] { [] }

    func savedCollections() async throws -> [PublicCollectionSummary] { [] }

    func setCollectionSaved(slug: String, saved: Bool) async throws {
        throw StubError.unsupported
    }
}
