import Foundation

/// One non-work match from `search/cross/`: a person, periodical, publisher…
/// The work branch of that endpoint is not used; works come from `works/`.
public struct CrossSearchHit: Decodable, Hashable, Sendable, Identifiable {
    public let entityType: String
    public let id: UUID
    public let label: String
    public let description: String?
    public let birthYear: Int?
    public let deathYear: Int?

    public init(
        entityType: String,
        id: UUID,
        label: String,
        description: String? = nil,
        birthYear: Int? = nil,
        deathYear: Int? = nil
    ) {
        self.entityType = entityType
        self.id = id
        self.label = label
        self.description = description
        self.birthYear = birthYear
        self.deathYear = deathYear
    }

    public var isPerson: Bool { entityType == "person" }
    public var isPeriodical: Bool { entityType == "periodical" }

    public var lifeDates: String? {
        switch (birthYear, deathYear) {
        case let (birth?, death?): "\(birth)–\(death)"
        case let (birth?, nil): "\(birth)–"
        case let (nil, death?): "† \(death)"
        default: nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, label, description
        case entityType = "entity_type"
        case birthYear = "birth_year"
        case deathYear = "death_year"
    }
}

/// The `search/cross/` envelope. A row that does not decode (an entity kind
/// with a non-UUID id, a blank label) is dropped, not the whole answer.
public struct CrossSearchResults: Decodable, Sendable {
    public let results: [CrossSearchHit]

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = ((try? container.decode([LossyHit].self, forKey: .results)) ?? [])
            .compactMap(\.hit)
            .filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    enum CodingKeys: String, CodingKey {
        case results
    }

    private struct LossyHit: Decodable {
        let hit: CrossSearchHit?

        init(from decoder: any Decoder) throws {
            hit = try? CrossSearchHit(from: decoder)
        }
    }
}
