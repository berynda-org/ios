import Foundation

public enum APIEndpoint: Sendable, Equatable {
    case works(search: String?, page: Int)
    case worksFiltered(search: String?, page: Int, readableOnly: Bool, language: String?)
    case work(slug: String)
    case editions(workID: UUID)
    case workCollections(workID: UUID)
    case recommendedWorks(limit: Int)
    case accountProfile
    case bibliographyLists
    case bibliographyQuickAdd
    case bibliographyList(id: UUID)
    case bibliographyListItem(listID: UUID, itemID: UUID)
    case publicCollections
    case savedCollections
    case collectionSave(slug: String)
    case readerInfo(fileID: UUID)
    case readerContent(fileID: UUID, structuredText: Bool)
    case pagePDF(fileID: UUID, page: Int)
    case pageImage(fileID: UUID, page: Int, width: Int)
    case readingPosition(fileID: UUID)
    case continueReading(limit: Int)

    func url(relativeTo baseURL: URL) -> URL? {
        let path: String
        var queryItems: [URLQueryItem] = []

        switch self {
        case let .works(search, page):
            path = "works/"
            queryItems.append(.init(name: "page", value: String(page)))
            if let normalizedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines),
               !normalizedSearch.isEmpty {
                // The public catalogue uses its prefix-aware `q` filter.
                // DRF's conventional `search` parameter is not enabled on
                // this endpoint, so sending it silently returned the full
                // catalogue instead of search results.
                queryItems.append(.init(name: "q", value: normalizedSearch))
            }
        case let .worksFiltered(search, page, readableOnly, language):
            path = "works/"
            queryItems.append(.init(name: "page", value: String(max(page, 1))))
            if let normalizedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines),
               !normalizedSearch.isEmpty {
                queryItems.append(.init(name: "q", value: normalizedSearch))
            }
            if readableOnly {
                queryItems.append(.init(name: "has_text", value: "true"))
            }
            if let language, !language.isEmpty {
                queryItems.append(.init(name: "language", value: language))
            }
        case let .work(slug):
            path = "works/\(Self.encodePathSegment(slug))/"
        case let .editions(workID):
            path = "works/\(workID.uuidString.lowercased())/editions/"
        case let .workCollections(workID):
            path = "works/\(workID.uuidString.lowercased())/collections/"
        case let .recommendedWorks(limit):
            path = "works/recommended/"
            // Clamped client-side too, so a caller cannot make the request the
            // server will only reject or silently bound.
            queryItems.append(.init(name: "limit", value: String(min(max(limit, 1), 48))))
        case .accountProfile:
            path = "auth/me/"
        case .bibliographyLists:
            path = "lists/"
        case .bibliographyQuickAdd:
            path = "lists/quick-add/"
        case let .bibliographyList(id):
            path = "lists/\(id.uuidString.lowercased())/"
        case let .bibliographyListItem(listID, itemID):
            path = "lists/\(listID.uuidString.lowercased())/items/\(itemID.uuidString.lowercased())/"
        case .publicCollections:
            path = "collections/"
        case .savedCollections:
            path = "auth/me/saved-collections/"
        case let .collectionSave(slug):
            path = "collections/\(Self.encodePathSegment(slug))/save/"
        case let .readerInfo(fileID):
            path = "files/\(fileID.uuidString.lowercased())/reader-info/"
        case let .readerContent(fileID, structuredText):
            path = "files/\(fileID.uuidString.lowercased())/reader-content/"
            if structuredText {
                queryItems.append(.init(name: "delivery", value: "json"))
            }
        case let .pagePDF(fileID, page):
            path = "files/\(fileID.uuidString.lowercased())/pages/\(max(page, 1)).pdf"
        case let .pageImage(fileID, page, width):
            path = "files/\(fileID.uuidString.lowercased())/pages/\(max(page, 1))/"
            queryItems.append(.init(name: "width", value: String(min(max(width, 180), 2_000))))
        case let .readingPosition(fileID):
            path = "files/\(fileID.uuidString.lowercased())/reading-position/"
        case let .continueReading(limit):
            path = "auth/me/reading/"
            queryItems.append(.init(name: "limit", value: String(min(max(limit, 1), 50))))
        }

        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url?.absoluteURL
    }

    private static func encodePathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
