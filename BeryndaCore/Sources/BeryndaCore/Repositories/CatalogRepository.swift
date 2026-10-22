import Foundation

public protocol CatalogRepository: Sendable {
    func works(search: String?, page: Int) async throws -> PaginatedResponse<WorkSummary>
    func works(
        search: String?,
        page: Int,
        filters: WorkFilters
    ) async throws -> PaginatedResponse<WorkSummary>
    /// Filter options and their counts for the same search and filters.
    func facets(search: String?, filters: WorkFilters) async throws -> WorkFacets
    /// One page of topics. `parent` is `"root"` or a parent slug; see
    /// `APIEndpoint.topics` for why the result must still be checked.
    func topics(parent: String?, search: String?, page: Int) async throws -> PaginatedResponse<TopicSummary>
    func topic(slug: String) async throws -> TopicSummary
    /// Non-work matches for a query of at least two characters.
    func crossSearch(query: String, types: [String], limit: Int) async throws -> [CrossSearchHit]
    func periodicals(search: String?, page: Int) async throws -> PaginatedResponse<PeriodicalSummary>
    /// By UUID or slug.
    func periodical(identifier: String) async throws -> PeriodicalSummary
    func periodicalYears(identifier: String) async throws -> [PeriodicalYear]
    func periodicalIssues(identifier: String, year: Int) async throws -> [PeriodicalIssue]
    func works(issueID: UUID, page: Int, readableOnly: Bool) async throws -> PaginatedResponse<PeriodicalIssueWork>
    /// Where a work was published; empty for most works.
    func periodicalLinks(workID: UUID) async throws -> [WorkPeriodicalLink]
    func author(id: UUID) async throws -> AuthorSummary
    func works(authorID: UUID, page: Int, readableOnly: Bool) async throws -> PaginatedResponse<WorkSummary>
    func work(identifier: String) async throws -> WorkSummary
    func editions(workID: UUID) async throws -> [EditionSummary]
    /// Public collections that contain this work.
    func collections(workID: UUID) async throws -> [PublicCollectionSummary]
    /// A shelf of works worth opening. Not personalised — the server ranks
    /// only the work, so every reader sees the same thing.
    func recommended(limit: Int) async throws -> [WorkSummary]
}

public extension CatalogRepository {
    func author(id: UUID) async throws -> AuthorSummary { throw APIError.invalidResponse }
    func topics(parent: String?, search: String?, page: Int) async throws -> PaginatedResponse<TopicSummary> {
        throw APIError.invalidResponse
    }
    func topic(slug: String) async throws -> TopicSummary { throw APIError.invalidResponse }
    func crossSearch(query: String, types: [String], limit: Int) async throws -> [CrossSearchHit] { [] }
    func periodicals(search: String?, page: Int) async throws -> PaginatedResponse<PeriodicalSummary> {
        throw APIError.invalidResponse
    }
    func periodical(identifier: String) async throws -> PeriodicalSummary { throw APIError.invalidResponse }
    func periodicalYears(identifier: String) async throws -> [PeriodicalYear] { throw APIError.invalidResponse }
    func periodicalIssues(identifier: String, year: Int) async throws -> [PeriodicalIssue] {
        throw APIError.invalidResponse
    }
    func works(issueID: UUID, page: Int, readableOnly: Bool) async throws -> PaginatedResponse<PeriodicalIssueWork> {
        throw APIError.invalidResponse
    }
    func periodicalLinks(workID: UUID) async throws -> [WorkPeriodicalLink] { [] }
    func works(authorID: UUID, page: Int, readableOnly: Bool) async throws -> PaginatedResponse<WorkSummary> {
        throw APIError.invalidResponse
    }

    // Defaulted so the UI-test and unit-test doubles do not each have to
    // restate a discovery surface they do not exercise.
    func collections(workID: UUID) async throws -> [PublicCollectionSummary] { [] }

    func recommended(limit: Int) async throws -> [WorkSummary] { [] }

    func works(
        search: String?,
        page: Int,
        filters: WorkFilters
    ) async throws -> PaginatedResponse<WorkSummary> {
        try await works(search: search, page: page)
    }

    /// No options is a usable answer: the sheet then offers only what is
    /// already selected.
    func facets(search: String?, filters: WorkFilters) async throws -> WorkFacets {
        WorkFacets(total: 0, languages: [], workTypes: [], yearBounds: nil)
    }
}

public struct LiveCatalogRepository: CatalogRepository {
    private let client: BeryndaAPIClient

    public init(client: BeryndaAPIClient) {
        self.client = client
    }

    public func works(search: String?, page: Int) async throws -> PaginatedResponse<WorkSummary> {
        try await client.request(.works(search: search, page: page))
    }

    public func works(
        search: String?,
        page: Int,
        filters: WorkFilters
    ) async throws -> PaginatedResponse<WorkSummary> {
        try await client.request(.worksFiltered(search: search, page: page, filters: filters))
    }

    public func facets(search: String?, filters: WorkFilters) async throws -> WorkFacets {
        try await client.request(.workFacets(search: search, filters: filters))
    }

    public func topics(parent: String?, search: String?, page: Int) async throws -> PaginatedResponse<TopicSummary> {
        try await client.request(.topics(parent: parent, search: search, page: page))
    }

    public func topic(slug: String) async throws -> TopicSummary {
        try await client.request(.topic(slug: slug))
    }

    public func crossSearch(query: String, types: [String], limit: Int) async throws -> [CrossSearchHit] {
        // The server rejects a query under two characters; asking would only
        // turn every first keystroke into an error.
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return [] }
        let response: CrossSearchResults = try await client.request(
            .crossSearch(query: query, types: types, limit: limit)
        )
        return response.results
    }

    public func periodicals(search: String?, page: Int) async throws -> PaginatedResponse<PeriodicalSummary> {
        try await client.request(.periodicals(search: search, page: page))
    }

    public func periodical(identifier: String) async throws -> PeriodicalSummary {
        try await client.request(.periodical(identifier: identifier))
    }

    public func periodicalYears(identifier: String) async throws -> [PeriodicalYear] {
        try await client.request(.periodicalYears(identifier: identifier))
    }

    public func periodicalIssues(identifier: String, year: Int) async throws -> [PeriodicalIssue] {
        try await client.request(.periodicalIssues(identifier: identifier, year: year))
    }

    public func works(issueID: UUID, page: Int, readableOnly: Bool) async throws -> PaginatedResponse<PeriodicalIssueWork> {
        try await client.request(.periodicalIssueWorks(issueID: issueID, page: page, readableOnly: readableOnly))
    }

    public func periodicalLinks(workID: UUID) async throws -> [WorkPeriodicalLink] {
        try await client.request(.workPeriodicalIssues(workID: workID))
    }

    public func author(id: UUID) async throws -> AuthorSummary {
        try await client.request(.author(id: id))
    }

    public func works(authorID: UUID, page: Int, readableOnly: Bool) async throws -> PaginatedResponse<WorkSummary> {
        try await client.request(.authorWorks(id: authorID, page: page, readableOnly: readableOnly))
    }

    public func work(identifier: String) async throws -> WorkSummary {
        try await client.request(.work(slug: identifier))
    }

    public func editions(workID: UUID) async throws -> [EditionSummary] {
        let response: EditionCollection = try await client.request(.editions(workID: workID))
        return response.values
    }

    public func collections(workID: UUID) async throws -> [PublicCollectionSummary] {
        try await client.request(.workCollections(workID: workID))
    }

    public func recommended(limit: Int) async throws -> [WorkSummary] {
        try await client.request(.recommendedWorks(limit: limit))
    }
}

private struct EditionCollection: Decodable, Sendable {
    let values: [EditionSummary]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let page = try? container.decode(PaginatedResponse<EditionSummary>.self) {
            values = page.results
        } else {
            values = try container.decode([EditionSummary].self)
        }
    }
}
