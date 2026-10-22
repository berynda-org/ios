import Foundation

/// A topic as a filter or a link target: the slug is what `works/?topic=`
/// takes, the name is only for display.
public struct TopicReference: Hashable, Sendable {
    public let slug: String
    public let name: String

    public init(slug: String, name: String) {
        self.slug = slug
        self.name = name
    }
}

/// The one filter set every work list uses — catalog, topic page — so the
/// same choices mean the same request everywhere.
///
/// One value per dimension: the API takes CSV, but a single choice is what the
/// filter sheet offers and what a reader can see at a glance.
public struct WorkFilters: Hashable, Sendable {
    /// `mobile_readable=true`: only works with a file this app can open.
    public var readableOnly: Bool
    public var language: String?
    public var workType: String?
    public var yearFrom: Int?
    public var yearTo: Int?
    public var topic: TopicReference?

    public init(
        readableOnly: Bool = false,
        language: String? = nil,
        workType: String? = nil,
        yearFrom: Int? = nil,
        yearTo: Int? = nil,
        topic: TopicReference? = nil
    ) {
        self.readableOnly = readableOnly
        self.language = language
        self.workType = workType
        self.yearFrom = yearFrom
        self.yearTo = yearTo
        self.topic = topic
    }

    /// Choices made in the filter sheet, i.e. everything but the readable
    /// switch, which has its own always-visible control.
    public var refinementCount: Int {
        [language != nil, workType != nil, yearFrom != nil || yearTo != nil, topic != nil]
            .filter { $0 }
            .count
    }

    public var hasRefinements: Bool { refinementCount > 0 }

    /// Nothing narrows the catalog: the shelves above it make sense only then.
    public var isUnfiltered: Bool { !readableOnly && !hasRefinements }

    /// The sheet's refinements cleared, the readable switch left as it was.
    public func clearingRefinements() -> WorkFilters {
        WorkFilters(readableOnly: readableOnly)
    }

    /// A range typed back to front still means the same span of years.
    public var normalizedYears: (from: Int?, to: Int?) {
        if let from = yearFrom, let to = yearTo, from > to { return (to, from) }
        return (yearFrom, yearTo)
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if readableOnly {
            items.append(.init(name: "mobile_readable", value: "true"))
        }
        if let language = language?.trimmed, !language.isEmpty {
            items.append(.init(name: "language", value: language))
        }
        if let workType = workType?.trimmed, !workType.isEmpty {
            items.append(.init(name: "work_type", value: workType))
        }
        let years = normalizedYears
        if let from = years.from {
            items.append(.init(name: "year_from", value: String(from)))
        }
        if let to = years.to {
            items.append(.init(name: "year_to", value: String(to)))
        }
        if let topic = topic?.slug.trimmed, !topic.isEmpty {
            items.append(.init(name: "topic", value: topic))
        }
        return items
    }
}

/// One option of a facet and how many works it would match.
public struct FacetOption: Hashable, Sendable, Identifiable {
    public let value: String
    public let count: Int

    public var id: String { value }

    public init(value: String, count: Int) {
        self.value = value
        self.count = count
    }
}

/// The parts of `works/facets/` the filter sheet offers. The response carries
/// more (genres, decades, availability counts); only what is shown is decoded,
/// and a missing group is an empty list rather than a failed decode.
public struct WorkFacets: Decodable, Sendable, Equatable {
    public let total: Int
    public let languages: [FacetOption]
    public let workTypes: [FacetOption]
    /// Earliest and latest decade with any work, for the year fields' hints.
    public let yearBounds: ClosedRange<Int>?

    public init(total: Int, languages: [FacetOption], workTypes: [FacetOption], yearBounds: ClosedRange<Int>?) {
        self.total = total
        self.languages = languages
        self.workTypes = workTypes
        self.yearBounds = yearBounds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = (try? container.decode(Int.self, forKey: .total)) ?? 0
        languages = ((try? container.decode([LanguageRow].self, forKey: .languages)) ?? [])
            .compactMap { row in
                guard let code = row.language?.trimmed, !code.isEmpty else { return nil }
                return FacetOption(value: code, count: row.count ?? 0)
            }
        workTypes = ((try? container.decode([WorkTypeRow].self, forKey: .workTypes)) ?? [])
            .compactMap { row in
                guard let type = row.workType?.trimmed, !type.isEmpty else { return nil }
                return FacetOption(value: type, count: row.count ?? 0)
            }
        let decades = ((try? container.decode([DecadeRow].self, forKey: .decades)) ?? [])
            .compactMap(\.decade)
        if let first = decades.min(), let last = decades.max() {
            yearBounds = first...(last + 9)
        } else {
            yearBounds = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case total, languages, decades
        case workTypes = "work_types"
    }

    private struct LanguageRow: Decodable {
        let language: String?
        let count: Int?
    }

    private struct WorkTypeRow: Decodable {
        let workType: String?
        let count: Int?

        enum CodingKeys: String, CodingKey {
            case count
            case workType = "work_type"
        }
    }

    private struct DecadeRow: Decodable {
        let decade: Int?
    }
}

/// Ukrainian names for the codes the API returns, matching the web catalog's
/// wording. An unknown code is shown as itself rather than hidden, so a new
/// value from the server is still selectable.
public enum CatalogVocabulary {
    public static func languageName(_ code: String) -> String {
        let key = code.trimmed.lowercased()
        return languageNames[key] ?? key.uppercased()
    }

    public static func workTypeName(_ value: String) -> String {
        let key = value.trimmed.lowercased()
        if let name = workTypeNames[key] { return name }
        let readable = key.replacingOccurrences(of: "_", with: " ")
        return readable.prefix(1).uppercased() + readable.dropFirst()
    }

    private static let languageNames: [String: String] = [
        "uk": "Українська",
        "orv": "Староукраїнська / руська",
        "cu": "Церковнослов’янська",
        "chu": "Церковнослов’янська",
        "ru": "Російська",
        "be": "Білоруська",
        "pl": "Польська",
        "cs": "Чеська",
        "sk": "Словацька",
        "bg": "Болгарська",
        "sr": "Сербська",
        "hr": "Хорватська",
        "en": "Англійська",
        "de": "Німецька",
        "fr": "Французька",
        "it": "Італійська",
        "es": "Іспанська",
        "pt": "Португальська",
        "nl": "Нідерландська",
        "sv": "Шведська",
        "ro": "Румунська",
        "hu": "Угорська",
        "lt": "Литовська",
        "lv": "Латвійська",
        "et": "Естонська",
        "yi": "Їдиш",
        "he": "Іврит",
        "tr": "Турецька",
        "ar": "Арабська",
        "fa": "Перська",
        "la": "Латина",
        "grc": "Давньогрецька",
        "el": "Грецька",
    ]

    private static let workTypeNames: [String: String] = [
        "book": "Книга",
        "novel": "Роман",
        "short_story": "Оповідання",
        "novella": "Повість",
        "poem": "Поезія",
        "poetry": "Поезія",
        "play": "Пʼєса",
        "essay": "Есей",
        "article": "Стаття",
        "newspaper_article": "Газетна стаття",
        "almanac_entry": "Альманах",
        "book_chapter": "Розділ",
        "dissertation": "Дисертація",
        "thesis": "Автореферат",
        "textbook": "Підручник",
        "encyclopedia_entry": "Стаття в енциклопедії",
        "manuscript": "Рукопис",
        "letter": "Лист",
        "speech": "Промова",
        "memoir": "Мемуари",
        "folk_song": "Народна пісня",
        "folklore": "Фольклор",
        "fiction": "Художня проза",
        "childrens_book": "Дитяча книга",
        "reference": "Довідник",
        "journal_issue": "Номер журналу",
        "conference_paper": "Доповідь",
        "preprint": "Препринт",
        "report": "Звіт",
        "review": "Рецензія",
        "volume": "Том",
        "patent": "Патент",
        "standard": "Стандарт",
        "dataset": "Набір даних",
        "map": "Мапа",
        "leaflet": "Летючка",
        "oral_history": "Усна історія",
        "other": "Інше",
    ]
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
