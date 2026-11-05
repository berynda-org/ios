public struct PaginatedResponse<Element: Decodable & Sendable>: Decodable, Sendable {
    public let count: Int
    public let next: String?
    public let previous: String?
    public let results: [Element]
}
