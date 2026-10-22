import Foundation

/// A journal, newspaper or almanac, as `periodicals/` lists it and
/// `periodicals/{id}/` returns it.
public struct PeriodicalSummary: Decodable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let slug: String?
    public let name: String
    public let periodicalType: String?
    public let issn: String?
    public let language: String?
    public let description: String?
    public let publicationPlace: String?
    public let frequency: String?
    public let foundedYear: Int?
    public let ceasedYear: Int?
    public let issuesCount: Int
    public let worksCount: Int

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        slug = try? container.decodeIfPresent(String.self, forKey: .slug)
        name = try container.decode(String.self, forKey: .name)
        periodicalType = try? container.decodeIfPresent(String.self, forKey: .periodicalType)
        issn = try? container.decodeIfPresent(String.self, forKey: .issn)
        language = try? container.decodeIfPresent(String.self, forKey: .language)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        publicationPlace = try? container.decodeIfPresent(String.self, forKey: .publicationPlace)
        frequency = try? container.decodeIfPresent(String.self, forKey: .frequency)
        foundedYear = try? container.decodeIfPresent(Int.self, forKey: .foundedYear)
        ceasedYear = try? container.decodeIfPresent(Int.self, forKey: .ceasedYear)
        issuesCount = (try? container.decode(Int.self, forKey: .issuesCount)) ?? 0
        worksCount = (try? container.decode(Int.self, forKey: .worksCount)) ?? 0
    }

    /// «1925–1933», «з 1925», «до 1933», or nothing when neither is known.
    public var yearsLabel: String? {
        switch (foundedYear, ceasedYear) {
        case let (from?, to?): from == to ? String(from) : "\(String(from))–\(String(to))"
        case let (from?, nil): "з \(String(from))"
        case let (nil, to?): "до \(String(to))"
        default: nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, slug, name, issn, language, description, frequency
        case periodicalType = "periodical_type"
        case publicationPlace = "publication_place"
        case foundedYear = "founded_year"
        case ceasedYear = "ceased_year"
        case issuesCount = "issues_count"
        case worksCount = "works_count"
    }
}

/// One row of `periodicals/{id}/years/`.
public struct PeriodicalYear: Decodable, Hashable, Sendable, Identifiable {
    public let year: Int
    public let issuesCount: Int
    public let worksCount: Int

    public var id: Int { year }

    public init(year: Int, issuesCount: Int, worksCount: Int) {
        self.year = year
        self.issuesCount = issuesCount
        self.worksCount = worksCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        year = try container.decode(Int.self, forKey: .year)
        issuesCount = (try? container.decode(Int.self, forKey: .issuesCount)) ?? 0
        worksCount = (try? container.decode(Int.self, forKey: .worksCount)) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case year
        case issuesCount = "issues_count"
        case worksCount = "works_count"
    }
}

/// An issue as `periodicals/{id}/issues/` lists it, or as a work's
/// «Опубліковано в» row nests it. Volume and issue numbers are free text on
/// the server («01 (348)»); a number sent instead is read as text too.
public struct PeriodicalIssue: Decodable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let periodicalID: UUID?
    public let periodicalName: String?
    public let periodicalSlug: String?
    public let volume: String?
    public let issue: String?
    public let year: Int?
    public let publicationDate: String?
    public let title: String?
    public let pageCount: Int?
    public let coverImageURL: URL?

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        periodicalID = try? container.decodeIfPresent(UUID.self, forKey: .periodical)
        periodicalName = try? container.decodeIfPresent(String.self, forKey: .periodicalName)
        periodicalSlug = try? container.decodeIfPresent(String.self, forKey: .periodicalSlug)
        volume = Self.text(container, .volume)
        issue = Self.text(container, .issue)
        year = try? container.decodeIfPresent(Int.self, forKey: .year)
        publicationDate = try? container.decodeIfPresent(String.self, forKey: .publicationDate)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        pageCount = try? container.decodeIfPresent(Int.self, forKey: .pageCount)
        coverImageURL = try? container.decodeIfPresent(URL.self, forKey: .coverImageURL)
    }

    /// The issue's own title, or one built from its numbers: «Т. 3, № 2 (1925)».
    public var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        var parts: [String] = []
        if let volume, !volume.isEmpty { parts.append("Т. \(volume)") }
        if let issue, !issue.isEmpty { parts.append("№ \(issue)") }
        var label = parts.isEmpty ? "Випуск" : parts.joined(separator: ", ")
        if let year { label += " (\(String(year)))" }
        return label
    }

    private static func text(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(number)
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id, periodical, volume, issue, year, title
        case periodicalName = "periodical_name"
        case periodicalSlug = "periodical_slug"
        case publicationDate = "publication_date"
        case pageCount = "page_count"
        case coverImageURL = "cover_image_url"
    }
}

/// A work card on an issue page, with where in the issue it sits.
public struct PeriodicalIssueWork: Decodable, Hashable, Sendable, Identifiable {
    public let work: WorkSummary
    /// Free text from the server, e.g. «12–18».
    public let issuePages: String?

    public var id: UUID { work.id }

    public init(from decoder: any Decoder) throws {
        work = try WorkSummary(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        issuePages = (try? container.decodeIfPresent(String.self, forKey: .issuePages))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }

    enum CodingKeys: String, CodingKey {
        case issuePages = "issue_pages"
    }
}

/// One «Опубліковано в» row of `works/{id}/periodical-issues/`.
public struct WorkPeriodicalLink: Decodable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let issue: PeriodicalIssue
    public let pages: String?
    public let articleNumber: String?
    public let columnName: String?

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        issue = try container.decode(PeriodicalIssue.self, forKey: .periodicalIssue)
        pages = (try? container.decodeIfPresent(String.self, forKey: .pages))?.nilIfBlank
        articleNumber = (try? container.decodeIfPresent(String.self, forKey: .articleNumber))?.nilIfBlank
        columnName = (try? container.decodeIfPresent(String.self, forKey: .columnName))?.nilIfBlank
    }

    enum CodingKeys: String, CodingKey {
        case id, pages
        case periodicalIssue = "periodical_issue"
        case articleNumber = "article_number"
        case columnName = "column_name"
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
