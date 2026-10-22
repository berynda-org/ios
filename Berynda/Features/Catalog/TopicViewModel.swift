import BeryndaCore
import Combine
import Foundation

/// One topic: its record (description, subtopics) and its works, read from
/// `works/?topic=` because only that list honours the readable filter.
@MainActor
final class TopicViewModel: ObservableObject {
    @Published private(set) var topic: TopicSummary?
    @Published private(set) var works: [WorkSummary] = []
    @Published private(set) var totalCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var nextPageError: String?
    @Published var readableOnly: Bool
    let reference: TopicReference
    private let repository: any CatalogRepository
    private var generation = 0
    private var currentPage = 0
    private var hasNextPage = false

    init(reference: TopicReference, readableOnly: Bool = false, repository: any CatalogRepository) {
        self.reference = reference
        self.readableOnly = readableOnly
        self.repository = repository
    }

    var title: String { topic?.name ?? reference.name }

    private var filters: WorkFilters {
        WorkFilters(readableOnly: readableOnly, topic: reference)
    }

    func load() async {
        generation += 1
        let requestGeneration = generation
        let requested = filters
        isLoading = true
        isLoadingNextPage = false
        errorMessage = nil
        nextPageError = nil
        defer { if generation == requestGeneration { isLoading = false } }
        // The record is decoration — name, description, subtopics — so a
        // failed lookup leaves the works list standing.
        let needsRecord = topic == nil
        async let record = fetchRecord(needed: needsRecord)
        do {
            let page = try await repository.works(search: nil, page: 1, filters: requested)
            let fetched = await record
            guard generation == requestGeneration, filters == requested else { return }
            if let fetched { topic = fetched }
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

    private func fetchRecord(needed: Bool) async -> TopicSummary? {
        guard needed else { return nil }
        return try? await repository.topic(slug: reference.slug)
    }

    func loadNextPage(after work: WorkSummary) async {
        guard work.id == works.last?.id, hasNextPage, !isLoading, !isLoadingNextPage else { return }
        let requestGeneration = generation
        let pageNumber = currentPage + 1
        let requested = filters
        isLoadingNextPage = true
        nextPageError = nil
        defer { if generation == requestGeneration { isLoadingNextPage = false } }
        do {
            let page = try await repository.works(search: nil, page: pageNumber, filters: requested)
            guard generation == requestGeneration, filters == requested else { return }
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
