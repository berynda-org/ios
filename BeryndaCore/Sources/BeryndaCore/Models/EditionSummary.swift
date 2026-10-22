import Foundation

public struct EditionSummary: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let work: UUID
    public let displayTitle: String
    public let language: String
    public let year: Int?
    public let publisherName: String?
    public let publicationPlace: String?
    public let pageCount: Int?
    public let readableFileID: UUID?
    public let canRead: Bool
    public let canDownload: Bool
    public let restrictionReason: String?
    /// Machine-readable reason, alongside the display text. The one value so
    /// far is `pages_not_ready`: a DjVu whose pages are still being split.
    public let restrictionCode: String?

    /// Readable soon rather than restricted: the reader opens once the
    /// server has rendered the pages.
    public var isAwaitingPages: Bool { restrictionCode == "pages_not_ready" }

    enum CodingKeys: String, CodingKey {
        case id, work, language, year
        case displayTitle = "display_title"
        case publisherName = "publisher_name"
        case publicationPlace = "publication_place"
        case pageCount = "page_count"
        case readableFileID = "readable_file_id"
        case canRead = "can_read"
        case canDownload = "can_download"
        case restrictionReason = "restriction_reason"
        case restrictionCode = "restriction_code"
    }
}
