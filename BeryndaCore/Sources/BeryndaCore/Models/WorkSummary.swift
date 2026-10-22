import Foundation

public struct WorkAuthor: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

/// One person's involvement in a work, with the role preserved.
///
/// The list endpoint flattens contributors into `authors`; only the detail
/// endpoint distinguishes a translator from an author. Keeping the role means
/// the bibliography can say which is which instead of running every name
/// together in one line.
public struct WorkContributor: Hashable, Sendable, Identifiable {
    public let personID: UUID
    public let role: String
    public let displayName: String

    public var id: String { "\(personID.uuidString)-\(role)" }

    public init(personID: UUID, role: String, displayName: String) {
        self.personID = personID
        self.role = role
        self.displayName = displayName
    }

    /// Roles the bibliography renders, in the order it renders them. Any other
    /// role is carried in `contributors` but not surfaced, so an unknown role
    /// from a newer API never appears as an unlabelled name.
    public static let presentedRoles = ["author", "translator", "compiler", "editor", "illustrator"]

    public var isPresented: Bool { Self.presentedRoles.contains(role) }
}

/// A controlled-vocabulary term (literary form, genre, topic).
public struct WorkTerm: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    /// Present for topics on the detail record; what makes a term linkable.
    public let slug: String?

    public init(id: UUID, name: String, slug: String? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
    }
}

public struct WorkSummary: Decodable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let slug: String
    public let title: String
    public let subtitle: String?
    public let description: String?
    public let language: String?
    public let firstPublishedYear: Int?
    public let workType: String?
    public let rightsSummary: String?
    public let pdStatus: String?
    public let pages: Int?
    public let authors: [WorkAuthor]
    public let editionsCount: Int
    public let hasTextFile: Bool
    public let coverImageURL: URL?
    public let coverTone: String?
    public let coverVariant: String?
    public let coverGlyph: String?

    // Detail-only enrichment. All optional: the same type decodes a list row
    // and a detail record, and a list row simply carries none of these.
    public let originalTitle: String?
    public let abstract: String?
    public let subtype: String?
    public let form: String?
    public let literaryForm: WorkTerm?
    public let genres: [WorkTerm]
    public let topics: [WorkTerm]
    public let additionalLanguages: [String]
    public let isCollection: Bool
    public let contributors: [WorkContributor]

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        slug = try container.decode(String.self, forKey: .slug)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        firstPublishedYear = try container.decodeIfPresent(Int.self, forKey: .firstPublishedYear)
        workType = try container.decodeIfPresent(String.self, forKey: .workType)
        rightsSummary = try container.decodeIfPresent(String.self, forKey: .rightsSummary)
        pdStatus = try container.decodeIfPresent(String.self, forKey: .pdStatus)
        pages = try container.decodeIfPresent(Int.self, forKey: .pages)
        editionsCount = (try? container.decode(Int.self, forKey: .editionsCount)) ?? 0
        hasTextFile = (try? container.decode(Bool.self, forKey: .hasTextFile)) ?? false
        coverImageURL = try container.decodeIfPresent(URL.self, forKey: .coverImageURL)
        coverTone = try container.decodeIfPresent(String.self, forKey: .coverTone)
        coverVariant = try container.decodeIfPresent(String.self, forKey: .coverVariant)
        coverGlyph = try container.decodeIfPresent(String.self, forKey: .coverGlyph)

        originalTitle = try container.decodeIfPresent(String.self, forKey: .originalTitle)
        abstract = try container.decodeIfPresent(String.self, forKey: .abstract)
        subtype = try container.decodeIfPresent(String.self, forKey: .subtype)
        form = try container.decodeIfPresent(String.self, forKey: .form)
        literaryForm = (try? container.decode(WorkTermPayload.self, forKey: .literaryForm))?.term
        genres = ((try? container.decode([WorkTermPayload].self, forKey: .genres)) ?? [])
            .compactMap { $0.term }
        topics = ((try? container.decode([WorkTermPayload].self, forKey: .topics)) ?? [])
            .compactMap { $0.term }
        additionalLanguages = (try? container.decode([String].self, forKey: .additionalLanguages)) ?? []
        isCollection = (try? container.decode(Bool.self, forKey: .isCollection)) ?? false

        let contributions = (try? container.decode([WorkContribution].self, forKey: .contributions)) ?? []
        contributors = contributions.map {
            WorkContributor(personID: $0.personID, role: $0.role, displayName: $0.displayName)
        }
        if let listAuthors = try? container.decode([WorkAuthor].self, forKey: .authors) {
            authors = listAuthors
        } else {
            authors = contributors
                .filter { $0.isPresented }
                .map { WorkAuthor(id: $0.personID, displayName: $0.displayName) }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, slug, title, subtitle, description, language, authors, pages
        case abstract, genres, topics, form, subtype
        case workType = "work_type"
        case rightsSummary = "rights_summary"
        case pdStatus = "pd_status"
        case firstPublishedYear = "first_published_year"
        case editionsCount = "editions_count"
        case hasTextFile = "has_text_file"
        case coverImageURL = "cover_image_url"
        case coverTone = "cover_tone"
        case coverVariant = "cover_variant"
        case coverGlyph = "cover_glyph"
        case contributions
        case originalTitle = "original_title"
        case literaryForm = "literary_form"
        case additionalLanguages = "additional_languages"
        case isCollection = "is_collection"
    }
}

/// One bibliography line: a role and every name filed under it.
///
/// A named type rather than a tuple because Swift has no key paths into tuple
/// elements, so `ForEach(_:)` and `map(\.role)` would both be unavailable.
public struct WorkContributorGroup: Hashable, Sendable, Identifiable {
    public let role: String
    public let names: [String]

    public var id: String { role }

    public init(role: String, names: [String]) {
        self.role = role
        self.names = names
    }
}

public extension WorkSummary {
    /// Contributors grouped for display, in `presentedRoles` order, with the
    /// names inside each role kept in the order the API returned them.
    var contributorsByRole: [WorkContributorGroup] {
        WorkContributor.presentedRoles.compactMap { role in
            let names = contributors
                .filter { $0.role == role }
                .map { $0.displayName }
            return names.isEmpty ? nil : WorkContributorGroup(role: role, names: names)
        }
    }

    /// True when the record carries detail-only fields, i.e. it came from the
    /// work endpoint rather than a list row.
    var isDetailed: Bool {
        !contributors.isEmpty
            || !genres.isEmpty
            || !topics.isEmpty
            || literaryForm != nil
            || originalTitle != nil
            || abstract != nil
    }
}

/// Nested term payloads are `{id, name, ...}` on both the list and detail
/// endpoints; anything without a usable id and name is dropped rather than
/// failing the whole decode.
private struct WorkTermPayload: Decodable {
    let id: UUID?
    let name: String?
    let nameEn: String?
    let slug: String?

    var term: WorkTerm? {
        guard let id, let name = name?.nilIfEmpty ?? nameEn?.nilIfEmpty else { return nil }
        return WorkTerm(id: id, name: name, slug: slug?.nilIfEmpty)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, slug
        case nameEn = "name_en"
    }
}

private struct WorkContribution: Decodable {
    let personID: UUID
    let role: String
    let personDisplayName: String
    let displayNameOverride: String?

    var displayName: String { displayNameOverride?.nilIfEmpty ?? personDisplayName }

    enum CodingKeys: String, CodingKey {
        case personID = "person_id"
        case role
        case personDisplayName = "person_display_name"
        case displayNameOverride = "display_name_override"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
