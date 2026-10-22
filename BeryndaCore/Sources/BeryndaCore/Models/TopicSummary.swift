import Foundation

/// A subtopic as the topic payload nests it: enough to list and link it.
public struct TopicChild: Decodable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let slug: String

    public var reference: TopicReference { TopicReference(slug: slug, name: name) }
}

/// A row of `topics/` or the record of `topics/{slug}/`; both share a shape.
public struct TopicSummary: Decodable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let slug: String
    public let parentSlug: String?
    public let parentName: String?
    public let description: String?
    public let workCount: Int?
    public let yearMin: Int?
    public let yearMax: Int?
    public let children: [TopicChild]

    public var reference: TopicReference { TopicReference(slug: slug, name: name) }

    /// A root has no parent. Used to keep a root listing correct whether or
    /// not the server applied `?parent=root`.
    public var isRoot: Bool { parentSlug?.isEmpty ?? true }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        slug = try container.decode(String.self, forKey: .slug)
        let ukrainian = try container.decodeIfPresent(String.self, forKey: .name)
        let english = try container.decodeIfPresent(String.self, forKey: .nameEn)
        name = [ukrainian, english, slug].compactMap { $0 }.first { !$0.isEmpty } ?? slug
        parentSlug = try container.decodeIfPresent(String.self, forKey: .parentSlug)
        parentName = try container.decodeIfPresent(String.self, forKey: .parentName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        workCount = try container.decodeIfPresent(Int.self, forKey: .workCount)
        yearMin = try container.decodeIfPresent(Int.self, forKey: .yearMin)
        yearMax = try container.decodeIfPresent(Int.self, forKey: .yearMax)
        // A malformed child is dropped rather than failing the whole topic.
        children = ((try? container.decode([LossyChild].self, forKey: .children)) ?? [])
            .compactMap(\.child)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, slug, description, children
        case nameEn = "name_en"
        case parentSlug = "parent_slug"
        case parentName = "parent_name"
        case workCount = "work_count"
        case yearMin = "year_min"
        case yearMax = "year_max"
    }

    private struct LossyChild: Decodable {
        let child: TopicChild?

        init(from decoder: any Decoder) throws {
            child = try? TopicChild(from: decoder)
        }
    }
}
