import BeryndaCore
import Combine
import Foundation

@MainActor
final class WorkDetailViewModel: ObservableObject {
    enum EditionsState {
        case loading
        case loaded([EditionSummary])
        case failed(String)
    }

    /// Starts as the row the catalog already had, so the header renders with
    /// no wait, and is replaced by the detail record once it arrives.
    @Published private(set) var work: WorkSummary
    @Published private(set) var editions: EditionsState = .loading
    /// Enrichment is a progressive improvement, never a gate: if it fails the
    /// page still shows the summary and the editions.
    @Published private(set) var isEnriching = false
    /// Public collections this work belongs to. Absent is the normal case, so
    /// a failure here is silent — the page is complete without it.
    @Published private(set) var collections: [PublicCollectionSummary] = []
    /// The periodical issues the work appeared in («Опубліковано в»). Most
    /// works have none, so a failure here is silent too.
    @Published private(set) var periodicalLinks: [WorkPeriodicalLink] = []

    private let repository: any CatalogRepository

    init(work: WorkSummary, repository: any CatalogRepository) {
        self.work = work
        self.repository = repository
    }

    func load() async {
        editions = .loading
        // A list row carries no contributors, genres, topics, or original
        // title, so without this the bibliography would be permanently thin.
        let needsEnrichment = !work.isDetailed
        isEnriching = needsEnrichment
        let identifier = work.slug
        let id = work.id

        // Both fetches are issued off the main actor so they overlap; awaiting
        // two main-actor methods would only have serialised them.
        async let detail: WorkSummary? = needsEnrichment
            ? Self.fetchDetail(identifier: identifier, from: repository)
            : nil
        async let editionOutcome = Self.fetchEditions(workID: id, from: repository)
        async let collectionList = Self.fetchCollections(workID: id, from: repository)
        async let linkList = Self.fetchPeriodicalLinks(workID: id, from: repository)
        let (detailed, outcome, collectionRows, links) = await (detail, editionOutcome, collectionList, linkList)
        collections = collectionRows
        periodicalLinks = links

        if let detailed, detailed.id == id {
            work = detailed
        }
        isEnriching = false
        apply(outcome)
    }

    /// Retries the editions section alone. A failure there is local to that
    /// section, so the rest of the page never reloads with it.
    func loadEditions() async {
        editions = .loading
        apply(await Self.fetchEditions(workID: work.id, from: repository))
    }

    private func apply(_ outcome: Result<[EditionSummary], Error>) {
        switch outcome {
        case let .success(list):
            editions = .loaded(list)
        case let .failure(error):
            guard !(error is CancellationError) else { return }
            editions = .failed(error.localizedDescription)
        }
    }

    private nonisolated static func fetchDetail(
        identifier: String,
        from repository: any CatalogRepository
    ) async -> WorkSummary? {
        // Deliberately swallowed: the summary is still a correct, useful page,
        // and a second error banner over one that already renders is noise.
        try? await repository.work(identifier: identifier)
    }

    private nonisolated static func fetchCollections(
        workID: UUID,
        from repository: any CatalogRepository
    ) async -> [PublicCollectionSummary] {
        // Silent on failure: a work page is correct and useful without the
        // collections it happens to appear in.
        ((try? await repository.collections(workID: workID)) ?? [])
    }

    private nonisolated static func fetchPeriodicalLinks(
        workID: UUID,
        from repository: any CatalogRepository
    ) async -> [WorkPeriodicalLink] {
        ((try? await repository.periodicalLinks(workID: workID)) ?? [])
    }

    private nonisolated static func fetchEditions(
        workID: UUID,
        from repository: any CatalogRepository
    ) async -> Result<[EditionSummary], Error> {
        do {
            return .success(try await repository.editions(workID: workID))
        } catch {
            return .failure(error)
        }
    }
}
