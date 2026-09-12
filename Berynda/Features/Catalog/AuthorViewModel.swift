import BeryndaCore
import Combine
import Foundation

@MainActor
final class AuthorViewModel: ObservableObject {
    @Published private(set) var author: AuthorSummary?
    @Published private(set) var works: [WorkSummary] = []
    @Published private(set) var totalCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var nextPageError: String?
    @Published var readableOnly = false
    let authorID: UUID
    private let repository: any CatalogRepository
    private var generation = 0
    private var currentPage = 0
    private var hasNextPage = false

    init(authorID: UUID, repository: any CatalogRepository) {
        self.authorID = authorID
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
            async let profile = repository.author(id: authorID)
            async let result = repository.works(authorID: authorID, page: 1, readableOnly: filter)
            let (person, page) = try await (profile, result)
            guard generation == requestGeneration, readableOnly == filter else { return }
            author = person
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

    func loadNextPage(after work: WorkSummary) async {
        guard work.id == works.last?.id, hasNextPage, !isLoading, !isLoadingNextPage else { return }
        let requestGeneration = generation
        let pageNumber = currentPage + 1
        let filter = readableOnly
        isLoadingNextPage = true
        nextPageError = nil
        defer { if generation == requestGeneration { isLoadingNextPage = false } }
        do {
            let page = try await repository.works(authorID: authorID, page: pageNumber, readableOnly: filter)
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
