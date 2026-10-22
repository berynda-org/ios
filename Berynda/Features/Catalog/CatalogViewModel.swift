import BeryndaCore
import Combine
import Foundation

@MainActor
final class CatalogViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded([WorkSummary], totalCount: Int)
        case failed(String)
        /// Offline with nothing to show from the network, but the reader has
        /// opened works before — those are more useful than an error alone.
        case offlineFallback([RecentlyViewedWork])
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var nextPageError: String?
    @Published var query = ""
    @Published var filters = WorkFilters()
    /// Options for the filter sheet. `nil` until first asked for, and left
    /// as it was when a lookup fails: the sheet still works without counts.
    @Published private(set) var facets: WorkFacets?
    /// People matching the search, shown above the works. Periodicals are
    /// asked for too but held back until the app has a periodical page:
    /// a hit that opens nothing is worse than no hit.
    @Published private(set) var authorHits: [CrossSearchHit] = []
    /// Server-ranked shelf shown above an unfiltered catalog. Empty is normal
    /// and not an error: it simply means nothing is being suggested.
    @Published private(set) var recommended: [WorkSummary] = []
    private let repository: any CatalogRepository
    private let recentlyViewed: RecentlyViewedStore?
    private var searchTask: Task<Void, Never>?
    private var entityTask: Task<Void, Never>?
    /// The term `authorHits` answers, so a filter change does not repeat
    /// a lookup the filters do not affect.
    private var entityTerm: String?
    private var currentPage = 0
    private var hasNextPage = false
    private var loadGeneration = 0
    private var facetsKey: FacetsKey?

    init(repository: any CatalogRepository, recentlyViewed: RecentlyViewedStore? = nil) {
        self.repository = repository
        self.recentlyViewed = recentlyViewed
    }

    deinit {
        searchTask?.cancel()
        entityTask?.cancel()
    }

    /// Loaded once per screen rather than per search: the shelf does not
    /// depend on the query, and refetching it on every keystroke would be
    /// pure waste.
    func loadRecommendedIfNeeded() async {
        guard recommended.isEmpty else { return }
        recommended = (try? await repository.recommended(limit: 12)) ?? []
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let requestedQuery = query.nilIfBlank
        let requestedFilters = filters
        isLoadingNextPage = false
        nextPageError = nil
        state = .loading
        refreshEntityHits()
        do {
            let page = try await repository.works(
                search: requestedQuery,
                page: 1,
                filters: requestedFilters
            )
            guard generation == loadGeneration,
                  requestedQuery == query.nilIfBlank,
                  requestedFilters == filters
            else { return }
            currentPage = 1
            hasNextPage = page.next != nil && page.results.count < page.count
            state = .loaded(page.results, totalCount: page.count)
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            // Only a request that never completed falls back. A 403, 404, or
            // malformed response is a real answer about the catalog and must
            // not be papered over with a list of things the reader happened to
            // open before.
            if case .transport = error as? APIError ?? .invalidResponse,
               let recent = await recentlyViewed?.recent(),
               !recent.isEmpty {
                state = .offlineFallback(recent)
                return
            }
            state = .failed(error.localizedDescription)
        }
    }

    func loadNextPageIfNeeded(after work: WorkSummary) async {
        guard case let .loaded(works, totalCount) = state,
              work.id == works.last?.id,
              hasNextPage,
              !isLoadingNextPage
        else { return }

        let generation = loadGeneration
        let requestedQuery = query.nilIfBlank
        let requestedFilters = filters
        let requestedPage = currentPage + 1
        isLoadingNextPage = true
        nextPageError = nil
        defer {
            if generation == loadGeneration { isLoadingNextPage = false }
        }

        do {
            let page = try await repository.works(
                search: requestedQuery,
                page: requestedPage,
                filters: requestedFilters
            )
            guard generation == loadGeneration,
                  requestedQuery == query.nilIfBlank,
                  requestedFilters == filters
            else { return }
            let knownIDs = Set(works.map(\.id))
            let newWorks = page.results.filter { !knownIDs.contains($0.id) }
            let combined = works + newWorks
            currentPage = requestedPage
            hasNextPage = page.next != nil && !page.results.isEmpty && combined.count < page.count
            state = .loaded(combined, totalCount: max(totalCount, page.count))
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            nextPageError = error.localizedDescription
        }
    }

    func retryNextPage() async {
        guard case let .loaded(works, _) = state, let last = works.last else { return }
        await loadNextPageIfNeeded(after: last)
    }

    /// Runs beside the works request rather than before it, so a slow or
    /// failed entity lookup never holds up or breaks the catalog.
    private func refreshEntityHits() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term != entityTerm else { return }
        entityTask?.cancel()
        guard term.count >= 2 else {
            authorHits = []
            entityTerm = term
            return
        }
        entityTask = Task { [weak self, repository] in
            let hits = (try? await repository.crossSearch(
                query: term,
                types: ["person", "periodical"],
                limit: 5
            )) ?? []
            guard !Task.isCancelled, let self,
                  self.query.trimmingCharacters(in: .whitespacesAndNewlines) == term
            else { return }
            self.authorHits = hits.filter(\.isPerson)
            self.entityTerm = term
        }
    }

    /// Fetched when the filter sheet opens, not per keystroke: the facet
    /// query is the heaviest catalog request, and its options matter only
    /// while the sheet is up.
    ///
    /// The options are counted without the sheet's own choices (language,
    /// type, years), so picking one does not hide the others; the search,
    /// the readable switch and the topic still narrow them.
    func loadFacetsIfNeeded() async {
        let key = FacetsKey(
            query: query.nilIfBlank,
            filters: WorkFilters(readableOnly: filters.readableOnly, topic: filters.topic)
        )
        guard key != facetsKey else { return }
        guard let loaded = try? await repository.facets(search: key.query, filters: key.filters) else { return }
        facets = loaded
        facetsKey = key
    }

    /// Everything the sheet set, cleared at once; the readable switch stays.
    func clearRefinements() {
        filters = filters.clearingRefinements()
    }

    func searchChanged() {
        searchTask?.cancel()
        loadGeneration += 1
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }
}

private struct FacetsKey: Equatable {
    let query: String?
    let filters: WorkFilters
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
