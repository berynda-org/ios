import Foundation

public struct ContinueReadingItem: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID { fileID }
    public let fileID: UUID
    public let editionID: UUID?
    public let workID: UUID?
    public let workTitle: String?
    public let editionYear: Int?
    public let progressPercent: Int?
    public let positionValue: String
    public let positionType: String
    public let lastReadAt: String
    public let coverImageURL: URL?

    enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
        case editionID = "edition_id"
        case workID = "work_id"
        case workTitle = "work_title"
        case editionYear = "edition_year"
        case progressPercent = "progress_percent"
        case positionValue = "position_value"
        case positionType = "position_type"
        case lastReadAt = "last_read_at"
        case coverImageURL = "cover_image_url"
    }
}

public struct ContinueReadingResponse: Codable, Sendable, Equatable {
    public let recentlyRead: [ContinueReadingItem]
    public let historyEnabled: Bool

    public init(recentlyRead: [ContinueReadingItem], historyEnabled: Bool) {
        self.recentlyRead = recentlyRead
        self.historyEnabled = historyEnabled
    }

    enum CodingKeys: String, CodingKey {
        case recentlyRead = "recently_read"
        case historyEnabled = "history_enabled"
    }
}

public struct BibliographyItem: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let work: UUID
    public let workTitle: String?
    public let workSlug: String?
    public let edition: UUID?
    public let editionYear: Int?
    public let editionTitle: String?
    public let file: UUID?
    public let positionType: String?
    public let positionValue: String?
    public let pageNumber: Int?
    public let note: String

    enum CodingKeys: String, CodingKey {
        case id, work, edition, file, note
        case workTitle = "work_title"
        case workSlug = "work_slug"
        case editionYear = "edition_year"
        case editionTitle = "edition_title"
        case positionType = "position_type"
        case positionValue = "position_value"
        case pageNumber = "page_number"
    }
}

// The server's `note` and the list's `description` are nullable text columns
// serialised verbatim. A new list has no description, so a strict `String`
// failed the create response and every later library load with it.
extension BibliographyItem {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        work = try container.decode(UUID.self, forKey: .work)
        workTitle = try container.decodeIfPresent(String.self, forKey: .workTitle)
        workSlug = try container.decodeIfPresent(String.self, forKey: .workSlug)
        edition = try container.decodeIfPresent(UUID.self, forKey: .edition)
        editionYear = try container.decodeIfPresent(Int.self, forKey: .editionYear)
        editionTitle = try container.decodeIfPresent(String.self, forKey: .editionTitle)
        file = try container.decodeIfPresent(UUID.self, forKey: .file)
        positionType = try container.decodeIfPresent(String.self, forKey: .positionType)
        positionValue = try container.decodeIfPresent(String.self, forKey: .positionValue)
        pageNumber = try container.decodeIfPresent(Int.self, forKey: .pageNumber)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

public struct BibliographyList: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let description: String
    public let citationStyle: String
    public let visibility: String
    public let isPinned: Bool
    public let workCount: Int
    public let items: [BibliographyItem]

    enum CodingKeys: String, CodingKey {
        case id, title, description, visibility, items
        case citationStyle = "citation_style"
        case isPinned = "is_pinned"
        case workCount = "work_count"
    }
}

extension BibliographyList {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        citationStyle = try container.decode(String.self, forKey: .citationStyle)
        visibility = try container.decode(String.self, forKey: .visibility)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        workCount = try container.decode(Int.self, forKey: .workCount)
        items = try container.decode([BibliographyItem].self, forKey: .items)
    }
}

public struct PublicCollectionSummary: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let slug: String
    public let name: String
    public let description: String
    public let category: String
    public let isFeatured: Bool
    public let coverImageURL: URL?
    public let workCount: Int
    public let featuredWorks: [CollectionWork]

    enum CodingKeys: String, CodingKey {
        case id, slug, name, description, category
        case isFeatured = "is_featured"
        case coverImageURL = "cover_image_url"
        case workCount = "work_count"
        case featuredWorks = "featured_works"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        slug = try container.decode(String.self, forKey: .slug)
        name = try container.decode(String.self, forKey: .name)
        // `Collection.description` and `.category` are nullable columns the API
        // serialises verbatim, so a single collection with no description would
        // otherwise fail the whole response and empty the shelf.
        // `try?` on `decode` covers both a null value and an absent key.
        description = (try? container.decode(String.self, forKey: .description)) ?? ""
        category = (try? container.decode(String.self, forKey: .category)) ?? ""
        isFeatured = (try? container.decode(Bool.self, forKey: .isFeatured)) ?? false
        coverImageURL = try container.decodeIfPresent(URL.self, forKey: .coverImageURL)
        workCount = (try? container.decode(Int.self, forKey: .workCount)) ?? 0
        featuredWorks = (try? container.decode([CollectionWork].self, forKey: .featuredWorks)) ?? []
    }
}

public struct CollectionWork: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let slug: String
    public let title: String
    public let subtitle: String?
    public let language: String?
    public let firstPublishedYear: Int?
    public let rightsSummary: String?
    public let coverTone: String?
    public let coverVariant: String?
    public let coverGlyph: String?

    enum CodingKeys: String, CodingKey {
        case id, slug, title, subtitle, language
        case firstPublishedYear = "first_published_year"
        case rightsSummary = "rights_summary"
        case coverTone = "cover_tone"
        case coverVariant = "cover_variant"
        case coverGlyph = "cover_glyph"
    }
}
