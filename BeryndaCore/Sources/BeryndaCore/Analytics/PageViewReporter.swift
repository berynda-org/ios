import Foundation

/// One row of the site's page-view analytics: the body of `POST pv/`.
///
/// The web beacon (`server/site/static/js/pageview.js`) sends the same
/// fields, so the admin's top-pages list counts web and app together. The
/// referrer and `utm_source` are left out: the app has neither.
public struct PageViewEvent: Encodable, Equatable, Sendable {
    public let visitorID: String
    public let sessionID: String
    public let pagePath: String
    public let interfaceLanguage: String?

    enum CodingKeys: String, CodingKey {
        case visitorID = "visitor_id"
        case sessionID = "session_id"
        case pagePath = "page_path"
        case interfaceLanguage = "interface_lang"
    }
}

/// Where the reporter keeps the visitor id and the session between launches.
public protocol PageViewStorage: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
}

/// `UserDefaults` is documented as thread-safe, hence `@unchecked`.
public struct UserDefaultsPageViewStorage: PageViewStorage, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func set(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

/// Counts each screen the app shows in the site's page-view analytics, the
/// way the web beacon counts each page load.
///
/// - The visitor id is a random UUID made once per install and kept.
/// - The session id rotates after 30 minutes without a screen view.
/// - Each report is one `POST pv/`, sent and forgotten: it never throws to
///   the caller, is never retried (a POST without an idempotency key is not
///   retried by the client) and is never queued offline. A lost view is
///   cheaper than a delayed or doubled one.
///
/// The server ignores a body it cannot use and always answers 204, so there
/// is nothing in the answer to read.
public actor PageViewReporter {
    /// The web beacon's `SESSION_TIMEOUT_MS`.
    public static let sessionTimeout: TimeInterval = 30 * 60
    /// The server's `page_path` limit.
    public static let maximumPathLength = 2_048
    /// The server's `interface_lang` limit.
    public static let maximumLanguageLength = 10

    static let visitorKey = "analytics.visitor_id"
    static let sessionKey = "analytics.session_id"
    static let sessionActivityKey = "analytics.session_last_activity"

    private let client: BeryndaAPIClient
    private let storage: any PageViewStorage
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        client: BeryndaAPIClient,
        storage: any PageViewStorage = UserDefaultsPageViewStorage(),
        now: @escaping @Sendable () -> Date = { Date() },
        makeID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.client = client
        self.storage = storage
        self.now = now
        self.makeID = makeID
    }

    /// Reports a screen in the background and returns at once. `path` is a
    /// web-style path such as `/works/kobzar`; anything from `?` or `#` on is
    /// dropped, so a query can never leave the device this way.
    public nonisolated func report(path: String, language: String?) {
        Task(priority: .utility) {
            await self.send(path: path, language: language)
        }
    }

    /// The awaitable form of `report`, for tests. Swallows every failure.
    public func send(path: String, language: String?) async {
        let event = nextEvent(path: path, language: language)
        do {
            try await client.send(.pageView, method: .post, body: event)
        } catch {
            // Analytics never surfaces an error and never retries.
        }
    }

    /// Builds the next event, rotating the session and stamping its activity.
    func nextEvent(path: String, language: String?) -> PageViewEvent {
        PageViewEvent(
            visitorID: visitorID(),
            sessionID: sessionID(),
            pagePath: Self.normalizedPath(path),
            interfaceLanguage: language
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : String($0.prefix(Self.maximumLanguageLength)) }
        )
    }

    private func visitorID() -> String {
        if let stored = storage.string(forKey: Self.visitorKey), UUID(uuidString: stored) != nil {
            return stored
        }
        let fresh = makeID().uuidString.lowercased()
        storage.set(fresh, forKey: Self.visitorKey)
        return fresh
    }

    private func sessionID() -> String {
        let current = now()
        let lastActivity = storage.string(forKey: Self.sessionActivityKey)
            .flatMap(TimeInterval.init)
            .map(Date.init(timeIntervalSince1970:))
        var session = storage.string(forKey: Self.sessionKey)
            .flatMap { UUID(uuidString: $0) != nil ? $0 : nil }
        if session == nil
            || lastActivity == nil
            || current.timeIntervalSince(lastActivity!) > Self.sessionTimeout {
            let fresh = makeID().uuidString.lowercased()
            storage.set(fresh, forKey: Self.sessionKey)
            session = fresh
        }
        storage.set(String(current.timeIntervalSince1970), forKey: Self.sessionActivityKey)
        return session!
    }

    /// The path without query or fragment, starting with `/`, within the
    /// server's length limit.
    static func normalizedPath(_ raw: String) -> String {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            path = String(path[..<cut])
        }
        if !path.hasPrefix("/") { path = "/" + path }
        return String(path.prefix(maximumPathLength))
    }
}

/// Web-equivalent paths for the app's screens, so a screen and the web page
/// that shows the same thing land on the same row of the top-pages list.
/// App-only screens live under `/app/`. No path carries a query or anything
/// personal.
public enum PageViewPath {
    public static let catalog = "/"
    /// The catalog while a query is typed; the query itself is never sent.
    public static let search = "/search"
    public static let topics = "/topics"
    public static let periodicals = "/periodicals"

    /// The web takes either; the slug is the canonical one.
    public static func work(slug: String?, id: UUID) -> String {
        if let slug = slug?.trimmingCharacters(in: .whitespacesAndNewlines), !slug.isEmpty {
            return "/works/\(segment(slug))"
        }
        return "/works/\(id.uuidString.lowercased())"
    }

    public static func person(id: UUID) -> String {
        "/persons/\(id.uuidString.lowercased())"
    }

    public static func reader(fileID: UUID) -> String {
        "/read/\(fileID.uuidString.lowercased())"
    }

    public static func topic(slug: String) -> String {
        "/topics/\(segment(slug))"
    }

    /// `identifier` is the periodical's slug or UUID, as the app knows it.
    public static func periodical(identifier: String) -> String {
        "/periodicals/\(segment(identifier.lowercased()))"
    }

    public static func periodicalIssue(periodicalIdentifier: String?, issueID: UUID) -> String {
        let issue = issueID.uuidString.lowercased()
        guard let periodical = periodicalIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !periodical.isEmpty
        else { return app("periodical-issues/\(issue)") }
        return "\(self.periodical(identifier: periodical))/issues/\(issue)"
    }

    public static func collection(slug: String) -> String {
        "/collections/\(segment(slug))"
    }

    /// An app-only screen, e.g. `app("library")` → `/app/library`.
    public static func app(_ name: String) -> String {
        "/app/\(name)"
    }

    private static func segment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%;")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
