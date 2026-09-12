import Foundation

public struct AuthorSummary: Decodable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let slug: String?
    public let displayName: String
    public let legalName: String?
    public let birthYear: Int?
    public let deathYear: Int?
    public let biography: String?

    public var lifeDates: String? {
        switch (birthYear, deathYear) {
        case let (birth?, death?): "\(birth)–\(death)"
        case let (birth?, nil): "\(birth)–"
        case let (nil, death?): "† \(death)"
        default: nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, slug
        case displayName = "display_name"
        case legalName = "legal_name"
        case birthYear = "birth_year"
        case deathYear = "death_year"
        case biography = "bio"
    }
}
