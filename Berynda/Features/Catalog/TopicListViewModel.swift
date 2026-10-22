import BeryndaCore
import Combine
import Foundation

/// Root topics, or every topic matching a search.
///
/// Roots are asked for with `parent=root` and checked here as well: a server
/// without that filter answers with every topic, so the rows are filtered on
/// `parent_slug` and pages are walked until one has something to show.
@MainActor
final class TopicListViewModel: ObservableObject {
    enum State {
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var topics: [TopicSummary] = []
    @Published private(set) var isLoadingNextPage = false
    @Published var query = ""
    private let repository: any CatalogRepository
    private var generation = 0
    private var currentPage = 0
    private var hasNextPage = false
    private var searchTask: Task<Void, Never>?
    /// Bounds the walk past pages that hold no roots, so a server that
    /// ignores `parent` costs a few requests per scroll, never the whole list.
    private static let maxPagesPerFetch = 8

    init(repository: any CatalogRepository) {
        self.repository = repository
    }

    deinit { searchTask?.cancel() }

    var isSearching: Bool { searchTerm != nil }

    func load() async {
        generation += 1
        let requestGeneration = generation
        let term = searchTerm
        state = .loading
        isLoadingNextPage = false
        do {
            let fetched = try await fetch(from: 1, term: term)
            guard requestGeneration == generation else { return }
            topics = fetched.rows
            currentPage = fetched.lastPage
            hasNextPage = fetched.hasNext
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard requestGeneration == generation else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func loadNextPage(after topic: TopicSummary) async {
        guard case .loaded = state,
              topic.id == topics.last?.id,
              hasNextPage,
              !isLoadingNextPage
        else { return }
        let requestGeneration = generation
        let term = searchTerm
        isLoadingNextPage = true
        defer { if requestGeneration == generation { isLoadingNextPage = false } }
        guard let fetched = try? await fetch(from: currentPage + 1, term: term),
              requestGeneration == generation
        else { return }
        let known = Set(topics.map(\.id))
        topics.append(contentsOf: fetched.rows.filter { !known.contains($0.id) })
        currentPage = fetched.lastPage
        hasNextPage = fetched.hasNext
    }

    func searchChanged() {
        searchTask?.cancel()
        generation += 1
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    private var searchTerm: String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func fetch(
        from firstPage: Int,
        term: String?
    ) async throws -> (rows: [TopicSummary], lastPage: Int, hasNext: Bool) {
        var page = firstPage
        while true {
            let response = try await repository.topics(
                parent: term == nil ? "root" : nil,
                search: term,
                page: page
            )
            // A topic known to hold nothing is a dead end to open.
            let rows = response.results.filter { topic in
                (term != nil || topic.isRoot) && topic.workCount != 0
            }
            let hasNext = response.next != nil && !response.results.isEmpty
            if !rows.isEmpty || !hasNext || page - firstPage + 1 >= Self.maxPagesPerFetch {
                return (rows, page, hasNext)
            }
            page += 1
        }
    }
}
