import Foundation
import XCTest
import BeryndaCore
@testable import Berynda

/// Saving and unsaving public collections through the library model.
final class SavedCollectionsTests: XCTestCase {
    @MainActor
    func testSavingAnAlreadySavedCollectionMakesNoNetworkCall() async throws {
        let poetry = try Self.collection(slug: "poetry", name: "Поезія")
        let repository = LibraryRepositoryStub(catalog: [poetry], savedSlugs: ["poetry"])
        let model = await makeLibraryModel(repository: repository)
        await model.load()
        XCTAssertTrue(model.isCollectionSaved(poetry))

        let result = await model.setCollectionSaved(poetry, saved: true)

        XCTAssertEqual(result, .alreadySaved)
        let calls = await repository.saveCalls
        XCTAssertTrue(calls.isEmpty, "A duplicate save must not reach the network")
    }

    @MainActor
    func testADuplicateSaveIsCaughtBeforeTheLibraryWasEverLoaded() async throws {
        let poetry = try Self.collection(slug: "poetry", name: "Поезія")
        let repository = LibraryRepositoryStub(catalog: [poetry], savedSlugs: ["poetry"])
        let model = await makeLibraryModel(repository: repository)

        // No load(): the catalog offers a save before the Library tab opens,
        // so the model has to fetch the snapshot itself before deciding.
        let result = await model.setCollectionSaved(poetry, saved: true)

        XCTAssertEqual(result, .alreadySaved)
        let calls = await repository.saveCalls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(model.isCollectionSaved(poetry))
    }

    @MainActor
    func testUnsavingIssuesOneCallAndDropsTheCollectionFromTheSnapshot() async throws {
        let poetry = try Self.collection(slug: "poetry", name: "Поезія")
        let prose = try Self.collection(slug: "prose", name: "Проза")
        let repository = LibraryRepositoryStub(
            catalog: [poetry, prose],
            savedSlugs: ["poetry", "prose"]
        )
        let model = await makeLibraryModel(repository: repository)
        await model.load()

        let result = await model.setCollectionSaved(poetry, saved: false)

        XCTAssertEqual(result, .removed)
        let calls = await repository.saveCalls
        XCTAssertEqual(calls, [LibraryRepositoryStub.SaveCall(slug: "poetry", saved: false)])
        XCTAssertFalse(model.isCollectionSaved(poetry))
        XCTAssertTrue(model.isCollectionSaved(prose))
        guard case let .loaded(_, _, saved) = model.state else {
            return XCTFail("Expected the library to reload after unsaving, got \(model.state)")
        }
        XCTAssertEqual(saved.map(\.slug), ["prose"])
    }

    @MainActor
    func testSavingANewCollectionPostsOnceAndShowsUpInTheSnapshot() async throws {
        let poetry = try Self.collection(slug: "poetry", name: "Поезія")
        let prose = try Self.collection(slug: "prose", name: "Проза")
        let repository = LibraryRepositoryStub(catalog: [poetry, prose], savedSlugs: ["poetry"])
        let model = await makeLibraryModel(repository: repository)
        await model.load()
        XCTAssertFalse(model.isCollectionSaved(prose))

        let result = await model.setCollectionSaved(prose, saved: true)

        XCTAssertEqual(result, .saved)
        let calls = await repository.saveCalls
        XCTAssertEqual(calls, [LibraryRepositoryStub.SaveCall(slug: "prose", saved: true)])
        XCTAssertTrue(model.isCollectionSaved(prose))
        XCTAssertTrue(model.isCollectionSaved(poetry))
    }

    @MainActor
    func testAnUnknownCollectionIsNotReportedAsSaved() async throws {
        let poetry = try Self.collection(slug: "poetry", name: "Поезія")
        // Same fixture id as `poetry`: only the slug may tell them apart.
        let drama = try Self.collection(slug: "drama", name: "Драма")
        let repository = LibraryRepositoryStub(catalog: [poetry, drama], savedSlugs: ["poetry"])
        let model = await makeLibraryModel(repository: repository)
        await model.load()

        XCTAssertTrue(model.isCollectionSaved(poetry))
        XCTAssertFalse(model.isCollectionSaved(drama))
    }

    @MainActor
    func testNothingIsReportedSavedBeforeTheSnapshotLoads() async throws {
        let poetry = try Self.collection(slug: "poetry", name: "Поезія")
        let repository = LibraryRepositoryStub(catalog: [poetry], savedSlugs: ["poetry"])
        let model = await makeLibraryModel(repository: repository)

        XCTAssertFalse(model.isCollectionSaved(poetry))

        // What a save button does when it first appears.
        await model.loadIfNeeded()

        XCTAssertTrue(model.isCollectionSaved(poetry))
        let calls = await repository.saveCalls
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor
    func testSigningOutStopsReportingTheCollectionAsSaved() async throws {
        let poetry = try Self.collection(slug: "poetry", name: "Поезія")
        let repository = LibraryRepositoryStub(catalog: [poetry], savedSlugs: ["poetry"])
        let model = await makeLibraryModel(repository: repository)
        await model.loadIfNeeded()
        XCTAssertTrue(model.isCollectionSaved(poetry))

        await model.accountForObservation.signOut()

        XCTAssertFalse(
            model.isCollectionSaved(poetry),
            "A signed-out reader must not see the previous account's saved collections"
        )
        await model.loadIfNeeded()
        guard case .signedOut = model.state else {
            return XCTFail("Signing out should drop the snapshot, got \(model.state)")
        }
    }

    // MARK: - Fixtures

    /// A signed-in library model over `repository`, the way `AppEnvironment`
    /// wires one up. The library only serves an authenticated account, so
    /// the account signs in with the UI-test credentials first.
    @MainActor
    private func makeLibraryModel(repository: any LibraryRepository) async -> LibraryViewModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SavedCollectionsTests-\(UUID().uuidString)", isDirectory: true)
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

    /// Decoded rather than constructed: the core models expose no memberwise
    /// initializers. Every collection shares one id on purpose — the model
    /// must tell them apart by slug, the key the save endpoint uses.
    private static func collection(slug: String, name: String) throws -> PublicCollectionSummary {
        let json = """
        {
          "id": "77777777-7777-7777-7777-777777777777",
          "slug": "\(slug)",
          "name": "\(name)",
          "description": "",
          "category": "literature",
          "is_featured": false,
          "cover_image_url": null,
          "work_count": 3,
          "featured_works": []
        }
        """
        return try JSONDecoder().decode(PublicCollectionSummary.self, from: Data(json.utf8))
    }
}

/// A library that serves a configurable saved list and records every
/// save/unsave the model sends it.
private actor LibraryRepositoryStub: LibraryRepository {
    struct SaveCall: Equatable, Sendable {
        let slug: String
        let saved: Bool
    }

    enum StubError: Error {
        case unsupported
    }

    private let catalog: [PublicCollectionSummary]
    private var savedSlugs: [String]
    private(set) var saveCalls: [SaveCall] = []

    init(catalog: [PublicCollectionSummary], savedSlugs: [String]) {
        self.catalog = catalog
        self.savedSlugs = savedSlugs
    }

    func continueReading(limit: Int) async throws -> ContinueReadingResponse {
        ContinueReadingResponse(recentlyRead: [], historyEnabled: true)
    }

    func bibliographyLists() async throws -> [BibliographyList] { [] }

    func createList(title: String) async throws -> BibliographyList {
        throw StubError.unsupported
    }

    // This stub serves no lists; list editing is covered by
    // LibraryListEditingTests.
    func renameList(id: UUID, title: String) async throws -> BibliographyList {
        throw StubError.unsupported
    }

    func deleteList(id: UUID) async throws {
        throw StubError.unsupported
    }

    func removeItem(listID: UUID, itemID: UUID) async throws {
        throw StubError.unsupported
    }

    func quickAdd(
        workID: UUID?,
        fileID: UUID?,
        positionType: String?,
        positionValue: String?,
        pageNumber: Int?
    ) async throws -> BibliographyItem {
        throw StubError.unsupported
    }

    func publicCollections() async throws -> [PublicCollectionSummary] { catalog }

    func savedCollections() async throws -> [PublicCollectionSummary] {
        catalog.filter { savedSlugs.contains($0.slug) }
    }

    func setCollectionSaved(slug: String, saved: Bool) async throws {
        saveCalls.append(SaveCall(slug: slug, saved: saved))
        if saved {
            if !savedSlugs.contains(slug) { savedSlugs.append(slug) }
        } else {
            savedSlugs.removeAll { $0 == slug }
        }
    }
}
