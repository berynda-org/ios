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

    /// `BibliographyList.title` on the server is a `CharField(max_length=255)`
    /// that may not be blank. Django counts that length in code points, so it
    /// is checked on unicode scalars here: `String.count` counts grapheme
    /// clusters and would pass a title of combined emoji the server rejects.
    static let maximumListTitleLength = 255

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
        await load(keepingSnapshot: false)
    }

    /// Re-fetches after a mutation. The server renumbers a list's items and
    /// recounts it on every change, so the snapshot is replaced wholesale
    /// rather than patched by hand — but a loaded screen stays up meanwhile,
    /// so the list the reader just edited neither blinks to a spinner nor
    /// collapses.
    private func reload() async {
        await load(keepingSnapshot: true)
    }

    private func load(keepingSnapshot: Bool) async {
        guard account.state == .authenticated else {
            state = .signedOut
            return
        }
        if keepingSnapshot, case .loaded = state {
            // Left on screen until the fresh snapshot replaces it.
        } else {
            state = .loading
        }
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

    // Every mutation below claims `isMutating` straight after its guard and
    // before its first `await`. The guard is only a guard if nothing can
    // suspend between checking the flag and setting it: the snapshot fetch a
    // save may need first is such a suspension, and a second mutation started
    // from another screen during it used to pass the guard as well.

    func setCollectionSaved(_ collection: PublicCollectionSummary, saved: Bool) async -> SaveResult {
        guard account.state == .authenticated else { return .signInRequired }
        guard !isMutating else { return .inProgress }
        isMutating = true
        defer { isMutating = false }
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
        do {
            try await repository.setCollectionSaved(slug: collection.slug, saved: saved)
            await reload()
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
        isMutating = true
        defer { isMutating = false }
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
        do {
            _ = try await repository.quickAdd(
                workID: workID,
                fileID: fileID,
                positionType: page == nil ? nil : "page",
                positionValue: page.map(String.init),
                pageNumber: page
            )
            await reload()
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func createList(title: String) async -> Bool {
        guard account.state == .authenticated else { return false }
        guard !isMutating else { return false }
        guard let clean = Self.validListTitle(title) else { return false }
        isMutating = true
        defer { isMutating = false }
        do {
            _ = try await repository.createList(title: clean)
            await reload()
            return true
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
    }

    /// The title as the server will store it — trimmed, not blank and at most
    /// `maximumListTitleLength` code points — or nil if it would be refused.
    static func validListTitle(_ title: String) -> String? {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.unicodeScalars.count <= maximumListTitleLength else {
            return nil
        }
        return clean
    }

    func renameList(id: UUID, title: String) async -> SaveResult {
        guard account.state == .authenticated else { return .signInRequired }
        guard !isMutating else { return .inProgress }
        guard let clean = Self.validListTitle(title) else {
            return .failed(
                "Назва списку не може бути порожньою чи довшою за \(Self.maximumListTitleLength) символів."
            )
        }
        isMutating = true
        defer { isMutating = false }
        do {
            _ = try await repository.renameList(id: id, title: clean)
            await reload()
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func deleteList(id: UUID) async -> SaveResult {
        guard account.state == .authenticated else { return .signInRequired }
        guard !isMutating else { return .inProgress }
        isMutating = true
        defer { isMutating = false }
        do {
            try await repository.deleteList(id: id)
            await reload()
            return .removed
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func removeItem(listID: UUID, itemID: UUID) async -> SaveResult {
        guard account.state == .authenticated else { return .signInRequired }
        guard !isMutating else { return .inProgress }
        isMutating = true
        defer { isMutating = false }
        do {
            try await repository.removeItem(listID: listID, itemID: itemID)
            await reload()
            return .removed
        } catch {
            return .failed(error.localizedDescription)
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
