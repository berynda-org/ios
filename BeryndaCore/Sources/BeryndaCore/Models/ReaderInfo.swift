import Foundation

public enum ReaderFormat: String, Codable, Sendable {
    case text = "txt"
    case markdown = "md"
    case epub
    case pdf
    case djvu

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self).lowercased()
        guard let format = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unsupported reader format"
            )
        }
        self = format
    }
}

public enum PageDelivery: String, Codable, Sendable {
    case clientFull = "client_full"
    case clientPerPage = "client_per_page"
    case serverPages = "server_pages"
}

public struct ReaderBook: Codable, Sendable, Equatable {
    public let title: String
    public let subtitle: String?
    public let authors: [String]
    public let editionYear: Int?
    public let publisher: String?
    public let publicationPlace: String?
    public let coverImageURL: URL?

    enum CodingKeys: String, CodingKey {
        case title, subtitle, authors, publisher
        case editionYear = "edition_year"
        case publicationPlace = "publication_place"
        case coverImageURL = "cover_image_url"
    }
}

public struct ReaderRights: Codable, Sendable, Equatable {
    public let canRead: Bool
    public let canDownloadFile: Bool
    public let canDownloadPage: Bool
    public let canCopyText: Bool
    public let canPrint: Bool
    public let canShare: Bool
    public let restrictionReason: String?
    /// May be kept on the device for offline reading. Absent on servers that
    /// predate offline reading, which is the same as no.
    public let canSaveOffline: Bool

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canRead = try container.decode(Bool.self, forKey: .canRead)
        canDownloadFile = try container.decode(Bool.self, forKey: .canDownloadFile)
        canDownloadPage = try container.decode(Bool.self, forKey: .canDownloadPage)
        canCopyText = try container.decode(Bool.self, forKey: .canCopyText)
        canPrint = try container.decode(Bool.self, forKey: .canPrint)
        canShare = try container.decode(Bool.self, forKey: .canShare)
        restrictionReason = try container.decodeIfPresent(String.self, forKey: .restrictionReason)
        canSaveOffline = (try? container.decodeIfPresent(Bool.self, forKey: .canSaveOffline)) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case canRead = "can_read"
        case canDownloadFile = "can_download_file"
        case canDownloadPage = "can_download_page"
        case canCopyText = "can_copy_text"
        case canPrint = "can_print"
        case canShare = "can_share"
        case restrictionReason = "restriction_reason"
        case canSaveOffline = "can_save_offline"
    }
}

/// What reader-info allows the app to keep for offline reading.
public struct OfflinePolicy: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// txt/md/epub: the reader-content bytes.
        case content
        /// PDF/DjVu: every page image.
        case pages
        /// A kind this build does not know; nothing is saved for it, but the
        /// rest of reader-info still decodes.
        case unsupported

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unsupported
        }
    }

    public let kind: Kind
    public let totalPages: Int?
    public let maxAgeDays: Int

    public init(kind: Kind, totalPages: Int?, maxAgeDays: Int) {
        self.kind = kind
        self.totalPages = totalPages
        self.maxAgeDays = maxAgeDays
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        totalPages = try? container.decodeIfPresent(Int.self, forKey: .totalPages)
        maxAgeDays = max((try? container.decodeIfPresent(Int.self, forKey: .maxAgeDays)) ?? 30, 1)
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case totalPages = "total_pages"
        case maxAgeDays = "max_age_days"
    }
}

public struct ReadingPosition: Codable, Sendable, Equatable {
    public let positionType: String
    public let positionValue: String
    public let progressPercent: Int?
    public let totalPages: Int?
    public let lastReadAt: String?

    enum CodingKeys: String, CodingKey {
        case positionType = "position_type"
        case positionValue = "position_value"
        case progressPercent = "progress_percent"
        case totalPages = "total_pages"
        case lastReadAt = "last_read_at"
    }
}

public struct ReaderTOCEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let ordinal: Int
    public let title: String
    public let pageNumber: Int?
    public let anchor: String?
    public let level: Int
    public let workID: UUID?
    public let children: [ReaderTOCEntry]

    public init(
        id: UUID,
        ordinal: Int,
        title: String,
        pageNumber: Int?,
        anchor: String?,
        level: Int,
        workID: UUID?,
        children: [ReaderTOCEntry]
    ) {
        self.id = id
        self.ordinal = ordinal
        self.title = title
        self.pageNumber = pageNumber
        self.anchor = anchor
        self.level = level
        self.workID = workID
        self.children = children
    }

    enum CodingKeys: String, CodingKey {
        case id, ordinal, title, anchor, level, children
        case pageNumber = "page_number"
        case workID = "work_id"
    }
}

public struct ReaderPageLabel: Codable, Sendable, Equatable {
    public let page: Int
    public let label: String
    public let source: String

    public init(page: Int, label: String, source: String) {
        self.page = page
        self.label = label
        self.source = source
    }
}

public struct ReaderInfo: Codable, Sendable, Equatable {
    public let fileID: UUID
    public let editionID: UUID
    public let seriesID: UUID?
    public let workID: UUID
    public let book: ReaderBook
    public let mimeType: String
    public let fileSizeBytes: Int?
    public let renderingMode: ReaderFormat
    public let pageDelivery: PageDelivery
    public let pagesExtracted: Bool
    public let splitPending: Bool
    public let splitFailed: Bool
    public let totalPages: Int?
    public let hasTOC: Bool
    public let toc: [ReaderTOCEntry]
    public let readingPosition: ReadingPosition?
    public let rights: ReaderRights
    public let pageLabels: [ReaderPageLabel]
    /// `nil` when nothing may be kept now (or the server predates offline
    /// reading).
    public let offline: OfflinePolicy?

    enum CodingKeys: String, CodingKey {
        case book, toc, rights, offline
        case fileID = "file_id"
        case editionID = "edition_id"
        case seriesID = "series_id"
        case workID = "work_id"
        case mimeType = "mime_type"
        case fileSizeBytes = "file_size_bytes"
        case renderingMode = "rendering_mode"
        case pageDelivery = "page_delivery"
        case pagesExtracted = "pages_extracted"
        case splitPending = "split_pending"
        case splitFailed = "split_failed"
        case totalPages = "total_pages"
        case hasTOC = "has_toc"
        case readingPosition = "reading_position"
        case pageLabels = "page_labels"
    }
}

public enum ReaderResource: Sendable, Equatable {
    case structuredText(isMarkdown: Bool)
    case epub
    case fullPDF
    case pagePDF
    case pageImage
    case unsupported
}

public extension ReaderInfo {
    var resource: ReaderResource {
        switch renderingMode {
        case .text:
            return .structuredText(isMarkdown: false)
        case .markdown:
            return .structuredText(isMarkdown: true)
        case .epub:
            return .epub
        case .djvu:
            // DjVu has no client renderer: it is readable only as the JPEG
            // pages the server splits it into, and has no text layer.
            return pageDelivery == .serverPages ? .pageImage : .unsupported
        case .pdf:
            switch pageDelivery {
            case .clientFull:
                return rights.canDownloadFile ? .fullPDF : .pageImage
            case .clientPerPage:
                return rights.canDownloadPage ? .pagePDF : .pageImage
            case .serverPages:
                return .pageImage
            }
        }
    }

    /// Read page by page from a document (PDF, or DjVu page images), as
    /// opposed to reflowed text or a publication.
    var isPagedDocument: Bool {
        switch resource {
        case .fullPDF, .pagePDF, .pageImage: true
        case .structuredText, .epub, .unsupported: false
        }
    }
}

public struct TextReaderContent: Codable, Sendable, Equatable {
    public let body: String
    public let pageOffsets: [Int]

    enum CodingKeys: String, CodingKey {
        case body
        case pageOffsets = "page_offsets"
    }
}
