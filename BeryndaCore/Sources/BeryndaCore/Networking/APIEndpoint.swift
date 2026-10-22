import Foundation

public enum APIEndpoint: Sendable, Equatable {
    case works(search: String?, page: Int)
    case worksFiltered(search: String?, page: Int, filters: WorkFilters)
    /// Option counts for the filter sheet; takes the same parameters as
    /// `works/`, minus the page.
    case workFacets(search: String?, filters: WorkFilters)
    /// `parent` is `"root"` or a topic slug. Servers without the filter
    /// ignore it, so callers must not rely on it alone.
    case topics(parent: String?, search: String?, page: Int)
    case topic(slug: String)
    /// People, periodicals and other non-work entities matching a query.
    case crossSearch(query: String, types: [String], limit: Int)
    case periodicals(search: String?, page: Int)
    /// A periodical by UUID or slug; the server accepts either.
    case periodical(identifier: String)
    case periodicalYears(identifier: String)
    /// One year's issues, as a bare list.
    case periodicalIssues(identifier: String, year: Int)
    case periodicalIssueWorks(issueID: UUID, page: Int, readableOnly: Bool)
    case workPeriodicalIssues(workID: UUID)
    case author(id: UUID)
    case authorWorks(id: UUID, page: Int, readableOnly: Bool)
    case work(slug: String)
    case editions(workID: UUID)
    case workCollections(workID: UUID)
    case recommendedWorks(limit: Int)
    case accountProfile
    case bibliographyLists
    case bibliographyQuickAdd
    case bibliographyList(id: UUID)
    case bibliographyListItem(listID: UUID, itemID: UUID)
    case bibliographyListItems(listID: UUID)
    case publicCollections
    case savedCollections
    case collectionSave(slug: String)
    case readerInfo(fileID: UUID)
    case readerContent(fileID: UUID, structuredText: Bool)
    case pagePDF(fileID: UUID, page: Int)
    case pageImage(fileID: UUID, page: Int, width: Int)
    case readingPosition(fileID: UUID)
    /// POST: whether saved offline copies may still be kept.
    case offlineStatus
    case continueReading(limit: Int)
    /// POST: in-app feedback and support requests (also the web contact form).
    case contact

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
        case let .worksFiltered(search, page, filters):
            path = "works/"
            queryItems.append(.init(name: "page", value: String(max(page, 1))))
            if let normalizedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines),
               !normalizedSearch.isEmpty {
                queryItems.append(.init(name: "q", value: normalizedSearch))
            }
            queryItems.append(contentsOf: filters.queryItems)
        case let .workFacets(search, filters):
            path = "works/facets/"
            if let normalizedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines),
               !normalizedSearch.isEmpty {
                queryItems.append(.init(name: "q", value: normalizedSearch))
            }
            queryItems.append(contentsOf: filters.queryItems)
        case let .topics(parent, search, page):
            path = "topics/"
            queryItems.append(.init(name: "page", value: String(max(page, 1))))
            if let parent, !parent.isEmpty {
                queryItems.append(.init(name: "parent", value: parent))
            }
            if let normalizedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines),
               !normalizedSearch.isEmpty {
                queryItems.append(.init(name: "search", value: normalizedSearch))
            }
        case let .topic(slug):
            path = "topics/\(Self.encodePathSegment(slug))/"
        case let .periodicals(search, page):
            path = "periodicals/"
            queryItems.append(.init(name: "page", value: String(max(page, 1))))
            if let normalizedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines),
               !normalizedSearch.isEmpty {
                queryItems.append(.init(name: "search", value: normalizedSearch))
            }
        case let .periodical(identifier):
            path = "periodicals/\(Self.encodePathSegment(identifier))/"
        case let .periodicalYears(identifier):
            path = "periodicals/\(Self.encodePathSegment(identifier))/years/"
        case let .periodicalIssues(identifier, year):
            path = "periodicals/\(Self.encodePathSegment(identifier))/issues/"
            queryItems.append(.init(name: "year", value: String(year)))
        case let .periodicalIssueWorks(issueID, page, readableOnly):
            path = "periodical-issues/\(issueID.uuidString.lowercased())/works/"
            queryItems.append(.init(name: "page", value: String(max(page, 1))))
            if readableOnly { queryItems.append(.init(name: "mobile_readable", value: "true")) }
        case let .workPeriodicalIssues(workID):
            path = "works/\(workID.uuidString.lowercased())/periodical-issues/"
        case let .crossSearch(query, types, limit):
            path = "search/cross/"
            queryItems.append(.init(name: "q", value: query.trimmingCharacters(in: .whitespacesAndNewlines)))
            queryItems.append(.init(name: "limit", value: String(min(max(limit, 1), 20))))
            if !types.isEmpty {
                queryItems.append(.init(name: "types", value: types.joined(separator: ",")))
            }
        case let .author(id):
            path = "persons/\(id.uuidString.lowercased())/"
        case let .authorWorks(id, page, readableOnly):
            path = "works/"
            queryItems.append(.init(name: "person_id", value: id.uuidString.lowercased()))
            queryItems.append(.init(name: "page", value: String(max(page, 1))))
            if readableOnly { queryItems.append(.init(name: "mobile_readable", value: "true")) }
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
        case let .bibliographyListItems(listID):
            path = "lists/\(listID.uuidString.lowercased())/items/"
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
        case .offlineStatus:
            path = "files/offline-status/"
        case let .readingPosition(fileID):
            path = "files/\(fileID.uuidString.lowercased())/reading-position/"
        case .contact:
            path = "contact/"
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
