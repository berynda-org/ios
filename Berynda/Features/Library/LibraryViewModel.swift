import BeryndaCore
import Combine
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    enum State {
        case signedOut
        case loading
        case loaded(
            continueReading: ContinueReadingResponse,
            lists: [BibliographyList],
            savedCollections: [PublicCollectionSummary]
        )
        case failed(String)
    }

    enum SaveResult: Equatable {
        case saved
        case removed
        case alreadySaved
        case inProgress
        case signInRequired
        case failed(String)
    }

    @Published private(set) var state: State = .signedOut
    @Published private(set) var isMutating = false
    @Published private(set) var publicCollections: [PublicCollectionSummary] = []
    @Published private(set) var discoveryError: String?
    private let repository: any LibraryRepository
    private let account: AccountViewModel
    var accountForObservation: AccountViewModel { account }

    init(repository: any LibraryRepository, account: AccountViewModel) {
        self.repository = repository
        self.account = account
    }

    func load() async {
        guard account.state == .authenticated else {
            state = .signedOut
            return
        }
        state = .loading
        do {
            async let recent = repository.continueReading(limit: 20)
            async let lists = repository.bibliographyLists()
            async let saved = repository.savedCollections()
            let values = try await (recent, lists, saved)
            state = .loaded(
                continueReading: values.0,
                lists: values.1,
                savedCollections: values.2
            )
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadPublicCollections() async {
        discoveryError = nil
        do {
            publicCollections = try await repository.publicCollections()
        } catch is CancellationError {
            return
        } catch {
            discoveryError = error.localizedDescription
        }
    }

    /// Brings the snapshot in line with the account for callers that only
    /// need it — the collection save buttons, which must know what is already
    /// saved before the reader ever opens the Library tab, and which re-run
    /// this whenever the account state changes. Signing out drops the snapshot
    /// so one reader's saved collections are never shown as saved to the
    /// next. A `.failed` snapshot is left alone while signed in: the library
    /// screen owns that retry.
    func loadIfNeeded() async {
        guard account.state == .authenticated else {
            if case .signedOut = state { return }
            state = .signedOut
            return
        }
        guard case .signedOut = state else { return }
        await load()
    }

    /// Whether `collection` is in the loaded snapshot of saved collections.
    ///
    /// Matched by slug: that is the key the save endpoint is addressed by, so
    /// it is the one identity guaranteed to agree between a catalog shelf, a
    /// work page and the saved list. Nothing is reported saved until the
    /// snapshot has loaded, nor to a reader who is no longer signed in.
    func isCollectionSaved(_ collection: PublicCollectionSummary) -> Bool {
        guard account.state == .authenticated,
              case let .loaded(_, _, saved) = state else { return false }
        return saved.contains { $0.slug == collection.slug }
    }

    func setCollectionSaved(_ collection: PublicCollectionSummary, saved: Bool) async -> SaveResult {
        guard account.state == .authenticated else { return .signInRequired }
        guard !isMutating else { return .inProgress }
        if saved {
            if case .loaded = state {
                // The current snapshot can be used for duplicate detection.
            } else {
                await load()
                guard case .loaded = state else {
                    if case let .failed(message) = state { return .failed(message) }
                    return .failed("Не вдалося перевірити збережені колекції.")
                }
            }
            // Re-saving would re-POST and report success over a no-op.
            if isCollectionSaved(collection) { return .alreadySaved }
        }
        isMutating = true
        defer { isMutating = false }
        do {
            try await repository.setCollectionSaved(slug: collection.slug, saved: saved)
            await load()
            return saved ? .saved : .removed
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func quickAdd(
        workID: UUID? = nil,
        fileID: UUID? = nil,
        page: Int? = nil
    ) async -> SaveResult {
        guard account.state == .authenticated else { return .signInRequired }
        guard !isMutating else { return .inProgress }
        if case .loaded = state {
            // The current snapshot can be used for duplicate detection.
        } else {
            await load()
            guard case .loaded = state else {
                if case let .failed(message) = state { return .failed(message) }
                return .failed("Не вдалося перевірити бібліотечний список.")
            }
        }
        if isDuplicate(workID: workID, fileID: fileID, page: page) {
            return .alreadySaved
        }
        isMutating = true
        defer { isMutating = false }
        do {
            _ = try await repository.quickAdd(
                workID: workID,
                fileID: fileID,
                positionType: page == nil ? nil : "page",
                positionValue: page.map(String.init),
                pageNumber: page
            )
            await load()
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func createList(title: String) async -> Bool {
        guard account.state == .authenticated else { return false }
        guard !isMutating else { return false }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        isMutating = true
        defer { isMutating = false }
        do {
            _ = try await repository.createList(title: clean)
            await load()
            return true
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
    }

    private func isDuplicate(workID: UUID?, fileID: UUID?, page: Int?) -> Bool {
        guard case let .loaded(_, lists, _) = state else { return false }
        return lists.flatMap(\.items).contains { item in
            if let fileID, item.file == fileID {
                return page == nil || item.pageNumber == page
            }
            if let workID { return item.work == workID && item.file == nil }
            return false
        }
    }
}
