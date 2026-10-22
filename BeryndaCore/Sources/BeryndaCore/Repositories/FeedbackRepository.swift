import Foundation

/// The two kinds of message the app's settings screen sends to the staff
/// inbox through `POST contact/`.
public enum FeedbackTopic: String, Encodable, Sendable {
    /// A 1–5 star rating with an optional comment.
    case appFeedback = "app_feedback"
    /// A support request that needs a reply address.
    case appSupport = "app_support"
}

/// Where the message came from, so staff can reproduce a problem. Nothing
/// here identifies the device or the person.
public struct FeedbackAppContext: Equatable, Sendable {
    public let platform: String
    /// `"1.2.0 (45)"`.
    public let appVersion: String
    /// `"iOS 26.1"`.
    public let osVersion: String
    /// The hardware identifier, e.g. `"iPhone16,2"`.
    public let deviceModel: String
    /// The interface language, e.g. `"uk-UA"`.
    public let locale: String

    public init(platform: String = "ios", appVersion: String, osVersion: String, deviceModel: String, locale: String) {
        self.platform = platform
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.locale = locale
    }
}

/// What the client checks before sending; the server applies the same rules.
public enum FeedbackValidationError: Error, Equatable, Sendable {
    case ratingRequired
    case messageTooShort(minimum: Int)
    case messageTooLong(maximum: Int)
    case emailRequired
    case emailInvalid
    case nameTooShort(minimum: Int)
}

/// The body of `POST contact/`. Built only through `rating(…)` or
/// `support(…)`, which validate it. Absent optional fields are left out of
/// the JSON, so a signed-in caller's name and email are filled in by the
/// server from the account.
public struct FeedbackSubmission: Encodable, Equatable, Sendable {
    public static let maximumMessageLength = 5_000
    public static let minimumSupportMessageLength = 10
    public static let minimumNameLength = 2

    public let topic: FeedbackTopic
    public let rating: Int?
    public let message: String
    public let senderName: String?
    public let senderEmail: String?
    public let platform: String
    public let appVersion: String
    public let osVersion: String
    public let deviceModel: String
    public let locale: String

    enum CodingKeys: String, CodingKey {
        case topic
        case rating
        case message
        case senderName = "sender_name"
        case senderEmail = "sender_email"
        case platform
        case appVersion = "app_version"
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case locale
    }

    private init(
        topic: FeedbackTopic,
        rating: Int?,
        message: String,
        senderName: String?,
        senderEmail: String?,
        context: FeedbackAppContext
    ) {
        self.topic = topic
        self.rating = rating
        self.message = message
        self.senderName = senderName
        self.senderEmail = senderEmail
        platform = context.platform
        appVersion = String(context.appVersion.prefix(32))
        osVersion = String(context.osVersion.prefix(64))
        deviceModel = String(context.deviceModel.prefix(64))
        locale = String(context.locale.prefix(16))
    }

    /// «Оцінити застосунок»: stars are required, everything else optional.
    /// Pass no name or email for a signed-in reader; the server takes them
    /// from the account.
    public static func rating(
        _ rating: Int?,
        comment: String,
        name: String? = nil,
        email: String? = nil,
        context: FeedbackAppContext
    ) throws -> FeedbackSubmission {
        guard let rating, (1...5).contains(rating) else { throw FeedbackValidationError.ratingRequired }
        let message = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.count <= maximumMessageLength else {
            throw FeedbackValidationError.messageTooLong(maximum: maximumMessageLength)
        }
        return FeedbackSubmission(
            topic: .appFeedback,
            rating: rating,
            message: message,
            senderName: try optionalName(name),
            senderEmail: try optionalEmail(email),
            context: context
        )
    }

    /// «Написати в підтримку»: a message of at least ten characters and,
    /// unless `isSignedIn`, a reply address.
    public static func support(
        message: String,
        email: String?,
        isSignedIn: Bool,
        context: FeedbackAppContext
    ) throws -> FeedbackSubmission {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= minimumSupportMessageLength else {
            throw FeedbackValidationError.messageTooShort(minimum: minimumSupportMessageLength)
        }
        guard text.count <= maximumMessageLength else {
            throw FeedbackValidationError.messageTooLong(maximum: maximumMessageLength)
        }
        let address = try optionalEmail(email)
        if address == nil, !isSignedIn { throw FeedbackValidationError.emailRequired }
        return FeedbackSubmission(
            topic: .appSupport,
            rating: nil,
            message: text,
            senderName: nil,
            senderEmail: address,
            context: context
        )
    }

    private static func optionalName(_ name: String?) throws -> String? {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count >= minimumNameLength else {
            throw FeedbackValidationError.nameTooShort(minimum: minimumNameLength)
        }
        return String(trimmed.prefix(200))
    }

    private static func optionalEmail(_ email: String?) throws -> String? {
        let trimmed = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        guard isPlausibleEmail(trimmed) else { throw FeedbackValidationError.emailInvalid }
        return trimmed
    }

    /// One `@`, something before it, a dot in the domain, no spaces. The
    /// server does the real check.
    static func isPlausibleEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !value.contains(" ") else { return false }
        let domain = parts[1]
        guard let dot = domain.lastIndex(of: "."), dot != domain.startIndex else { return false }
        return domain.index(after: dot) != domain.endIndex
    }
}

/// `201 {"ok": true, "id": "<uuid>"}`.
public struct FeedbackReceipt: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let id: String?

    public init(ok: Bool, id: String?) {
        self.ok = ok
        self.id = id
    }
}

public protocol FeedbackRepository: Sendable {
    func submit(_ submission: FeedbackSubmission) async throws -> FeedbackReceipt
}

/// Sends through the API client, which adds the reader's JWT when signed in
/// and nothing otherwise (the endpoint accepts both).
public struct LiveFeedbackRepository: FeedbackRepository {
    private let client: BeryndaAPIClient

    public init(client: BeryndaAPIClient) {
        self.client = client
    }

    public func submit(_ submission: FeedbackSubmission) async throws -> FeedbackReceipt {
        try await client.request(.contact, method: .post, body: submission)
    }
}
