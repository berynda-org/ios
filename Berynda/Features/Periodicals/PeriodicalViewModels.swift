import BeryndaCore
import Combine
import Foundation

/// «Періодика»: every periodical, or those matching a search, page by page.
@MainActor
final class PeriodicalListViewModel: ObservableObject {
    enum State {
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var periodicals: [PeriodicalSummary] = []
    @Published private(set) var isLoadingNextPage = false
    @Published var query = ""
    private let repository: any CatalogRepository
    private var generation = 0
    private var currentPage = 0
    private var hasNextPage = false
    private var searchTask: Task<Void, Never>?

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
            let page = try await repository.periodicals(search: term, page: 1)
            guard requestGeneration == generation else { return }
            periodicals = page.results
            currentPage = 1
            hasNextPage = page.next != nil && !page.results.isEmpty
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard requestGeneration == generation else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func loadNextPage(after periodical: PeriodicalSummary) async {
        guard case .loaded = state,
              periodical.id == periodicals.last?.id,
              hasNextPage,
              !isLoadingNextPage
        else { return }
        let requestGeneration = generation
        let term = searchTerm
        let pageNumber = currentPage + 1
        isLoadingNextPage = true
        defer { if requestGeneration == generation { isLoadingNextPage = false } }
        guard let page = try? await repository.periodicals(search: term, page: pageNumber),
              requestGeneration == generation
        else { return }
        let known = Set(periodicals.map(\.id))
        periodicals.append(contentsOf: page.results.filter { !known.contains($0.id) })
        currentPage = pageNumber
        hasNextPage = page.next != nil && !page.results.isEmpty
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
        return trimmed.count >= 2 ? trimmed : nil
    }
}

/// A periodical page: its record and its years, each year's issues fetched
/// the first time that year is opened.
@MainActor
final class PeriodicalViewModel: ObservableObject {
    enum IssuesState {
        case loading
        case loaded([PeriodicalIssue])
        case failed(String)
    }

    @Published private(set) var periodical: PeriodicalSummary?
    @Published private(set) var years: [PeriodicalYear] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var expandedYears: Set<Int> = []
    @Published private(set) var issuesByYear: [Int: IssuesState] = [:]
    let identifier: String
    let fallbackName: String
    private let repository: any CatalogRepository

    init(
        identifier: String,
        name: String,
        known: PeriodicalSummary? = nil,
        repository: any CatalogRepository
    ) {
        self.identifier = identifier
        self.fallbackName = name
        self.periodical = known
        self.repository = repository
    }

    var title: String { periodical?.name ?? fallbackName }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let needsRecord = periodical == nil
        async let record = fetchRecord(needed: needsRecord)
        do {
            let loadedYears = try await repository.periodicalYears(identifier: identifier)
            if let fetched = await record { periodical = fetched }
            years = loadedYears
            // A single year needs no extra tap.
            if loadedYears.count == 1, let only = loadedYears.first, expandedYears.isEmpty {
                await toggle(only.year)
            }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Opens or closes a year; its issues are fetched once and kept.
    func toggle(_ year: Int) async {
        if expandedYears.contains(year) {
            expandedYears.remove(year)
            return
        }
        expandedYears.insert(year)
        if case .loaded = issuesByYear[year] { return }
        await loadIssues(for: year)
    }

    func loadIssues(for year: Int) async {
        issuesByYear[year] = .loading
        do {
            let issues = try await repository.periodicalIssues(identifier: identifier, year: year)
            issuesByYear[year] = .loaded(issues)
        } catch is CancellationError {
            issuesByYear[year] = nil
        } catch {
            issuesByYear[year] = .failed(error.localizedDescription)
        }
    }

    private func fetchRecord(needed: Bool) async -> PeriodicalSummary? {
        guard needed else { return nil }
        // The years are the page; a missing record only costs the header.
        return try? await repository.periodical(identifier: identifier)
    }
}

/// An issue page: the works in it, under the reader's readable switch.
@MainActor
final class PeriodicalIssueViewModel: ObservableObject {
    @Published private(set) var works: [PeriodicalIssueWork] = []
    @Published private(set) var totalCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var nextPageError: String?
    @Published var readableOnly: Bool
    let issueID: UUID
    private let repository: any CatalogRepository
    private var generation = 0
    private var currentPage = 0
    private var hasNextPage = false

    init(issueID: UUID, readableOnly: Bool = false, repository: any CatalogRepository) {
        self.issueID = issueID
        self.readableOnly = readableOnly
        self.repository = repository
    }

    func load() async {
        generation += 1
        let requestGeneration = generation
        let filter = readableOnly
        isLoading = true
        isLoadingNextPage = false
        errorMessage = nil
        nextPageError = nil
        defer { if generation == requestGeneration { isLoading = false } }
        do {
            let page = try await repository.works(issueID: issueID, page: 1, readableOnly: filter)
            guard generation == requestGeneration, readableOnly == filter else { return }
            works = page.results
            totalCount = page.count
            currentPage = 1
            hasNextPage = page.next != nil && works.count < totalCount
        } catch is CancellationError {
        } catch {
            guard generation == requestGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadNextPage(after work: PeriodicalIssueWork) async {
        guard work.id == works.last?.id, hasNextPage, !isLoading, !isLoadingNextPage else { return }
        let requestGeneration = generation
        let pageNumber = currentPage + 1
        let filter = readableOnly
        isLoadingNextPage = true
        nextPageError = nil
        defer { if generation == requestGeneration { isLoadingNextPage = false } }
        do {
            let page = try await repository.works(issueID: issueID, page: pageNumber, readableOnly: filter)
            guard generation == requestGeneration, readableOnly == filter else { return }
            let existing = Set(works.map(\.id))
            works.append(contentsOf: page.results.filter { !existing.contains($0.id) })
            currentPage = pageNumber
            totalCount = page.count
            hasNextPage = page.next != nil && !page.results.isEmpty && works.count < totalCount
        } catch is CancellationError {
        } catch {
            guard generation == requestGeneration else { return }
            nextPageError = error.localizedDescription
        }
    }

    func retryNextPage() async {
        guard let last = works.last else { return }
        await loadNextPage(after: last)
    }
}
