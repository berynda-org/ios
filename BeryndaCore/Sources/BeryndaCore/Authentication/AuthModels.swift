import Foundation

public struct AuthTokens: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Format: Equatable, Sendable {
        case opaque
        case legacyJWT
    }

    public let access: String
    public let refresh: String
    /// When the access token stops working, if the server said so.
    public let accessExpiresAt: Date?
    /// When the refresh token stops working, if the server said so.
    public let refreshExpiresAt: Date?

    public init(
        access: String,
        refresh: String,
        accessExpiresAt: Date? = nil,
        refreshExpiresAt: Date? = nil
    ) throws {
        guard Self.isValidPair(access: access, refresh: refresh) else {
            throw SessionError.invalidToken
        }
        self.access = access
        self.refresh = refresh
        self.accessExpiresAt = accessExpiresAt
        self.refreshExpiresAt = refreshExpiresAt
    }

    /// Builds a pair from a token response, turning the relative lifetimes
    /// into dates measured from `receivedAt`, the moment the response arrived.
    public init(
        access: String,
        refresh: String,
        expiresIn: Int?,
        refreshExpiresIn: Int?,
        receivedAt: Date
    ) throws {
        try self.init(
            access: access,
            refresh: refresh,
            accessExpiresAt: Self.date(after: expiresIn, from: receivedAt),
            refreshExpiresAt: Self.date(after: refreshExpiresIn, from: receivedAt)
        )
    }

    public var format: Format {
        Self.isOpaque(access, prefix: Self.opaqueAccessPrefix) ? .opaque : .legacyJWT
    }

    /// True when the server's stated refresh lifetime has passed, so a refresh
    /// cannot succeed and the reader has to sign in again.
    public func isRefreshExpired(at now: Date) -> Bool {
        guard let refreshExpiresAt else { return false }
        return now >= refreshExpiresAt
    }

    public var description: String { "AuthTokens(<redacted>)" }
    public var debugDescription: String { description }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let access = try container.decode(String.self, forKey: .access)
        let refresh = try container.decode(String.self, forKey: .refresh)
        guard Self.isValidPair(access: access, refresh: refresh) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid token representation")
            )
        }
        self.access = access
        self.refresh = refresh
        // Records saved before opaque tokens have no lifetimes.
        accessExpiresAt = try container.decodeIfPresent(Date.self, forKey: .accessExpiresAt)
        refreshExpiresAt = try container.decodeIfPresent(Date.self, forKey: .refreshExpiresAt)
    }

    enum CodingKeys: String, CodingKey {
        case access
        case refresh
        case accessExpiresAt = "access_expires_at"
        case refreshExpiresAt = "refresh_expires_at"
    }

    static let opaqueAccessPrefix = "bat_"
    static let opaqueRefreshPrefix = "brt_"

    /// Both tokens opaque, or both legacy JWTs. A mixed pair never comes from
    /// the server and is rejected.
    static func isValidPair(access: String, refresh: String) -> Bool {
        (isOpaque(access, prefix: opaqueAccessPrefix) && isOpaque(refresh, prefix: opaqueRefreshPrefix))
            || (isLegacyJWT(access) && isLegacyJWT(refresh))
    }

    /// A value that may go into `Authorization: Bearer`.
    static func isValidAccessToken(_ value: String) -> Bool {
        isOpaque(value, prefix: opaqueAccessPrefix) || isLegacyJWT(value)
    }

    /// A value that may be sent to `auth/token/refresh/` or `auth/logout/`.
    static func isValidRefreshToken(_ value: String) -> Bool {
        isOpaque(value, prefix: opaqueRefreshPrefix) || isLegacyJWT(value)
    }

    /// The prefix followed by base64url text. The server sends 43 characters
    /// after the prefix today; the bound is loose so it can lengthen tokens
    /// without breaking installed apps. The content is never interpreted.
    static func isOpaque(_ value: String, prefix: String) -> Bool {
        guard value.hasPrefix(prefix) else { return false }
        let body = value.dropFirst(prefix.count)
        guard (32...512).contains(body.count) else { return false }
        return body.unicodeScalars.allSatisfy { base64URL.contains($0) }
    }

    /// Shape check only: legacy JWTs are no longer decoded.
    static func isLegacyJWT(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 16_384 else { return false }
        return value.unicodeScalars.allSatisfy { jwtCharacters.contains($0) }
            && value.split(separator: ".", omittingEmptySubsequences: false).count == 3
    }

    private static let base64URL = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    )
    private static let jwtCharacters = base64URL.union(CharacterSet(charactersIn: "."))

    private static func date(after seconds: Int?, from start: Date) -> Date? {
        guard let seconds, seconds > 0 else { return nil }
        return start.addingTimeInterval(TimeInterval(seconds))
    }
}

public struct UserProfile: Codable, Equatable, Sendable {
    public let id: UUID
    public let email: String
    public let displayName: String?
    public let bio: String?
    public let institutionName: String?
    public let uiLanguage: String
    public let privacySettings: [String: Bool]
    /// `false` for an Apple/Google-only account, which sets a password via
    /// the reset email. A server too old to say is taken to mean `true`.
    public let hasPassword: Bool
    /// Linked sign-in providers, e.g. `["apple"]`.
    public let socialProviders: [String]

    public init(
        id: UUID,
        email: String,
        displayName: String?,
        bio: String? = nil,
        institutionName: String? = nil,
        uiLanguage: String = "uk",
        privacySettings: [String: Bool] = [:],
        hasPassword: Bool = true,
        socialProviders: [String] = []
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.bio = bio
        self.institutionName = institutionName
        self.uiLanguage = uiLanguage
        self.privacySettings = privacySettings
        self.hasPassword = hasPassword
        self.socialProviders = socialProviders
    }

    /// How this account can confirm its deletion, before the server says.
    public var deletionMethods: [ReauthenticationMethod] {
        ReauthenticationMethod.available(hasPassword: hasPassword, socialProviders: socialProviders)
    }

    public var readingHistoryEnabled: Bool {
        privacySettings["reading_history_enabled"] ?? true
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        institutionName = try container.decodeIfPresent(String.self, forKey: .institutionName)
        uiLanguage = (try? container.decode(String.self, forKey: .uiLanguage)) ?? "uk"
        privacySettings = (try? container.decode([String: Bool].self, forKey: .privacySettings)) ?? [:]
        hasPassword = (try? container.decode(Bool.self, forKey: .hasPassword)) ?? true
        socialProviders = (try? container.decode([String].self, forKey: .socialProviders)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case bio
        case institutionName = "institution_name"
        case uiLanguage = "ui_language"
        case privacySettings = "privacy_settings"
        case hasPassword = "has_password"
        case socialProviders = "social_providers"
    }
}

public struct RegistrationResult: Codable, Equatable, Sendable {
    public let id: UUID
    public let email: String
    public let activation: String

    public init(id: UUID, email: String, activation: String) {
        self.id = id
        self.email = email
        self.activation = activation
    }

    public var requiresEmailConfirmation: Bool {
        activation == "email_confirmation_required"
    }
}

public struct AuthSession: Equatable, Sendable {
    public let tokens: AuthTokens
    public let user: UserProfile

    public init(tokens: AuthTokens, user: UserProfile) {
        self.tokens = tokens
        self.user = user
    }
}

public enum SessionState: Equatable, Sendable {
    case anonymous
    case authenticated
    case expired
}

public enum SessionError: Error, Equatable, Sendable {
    case invalidCredentials
    case invalidInput
    case invalidToken
    case expired
    case invalidResponse
    case unavailable
    case storage
    case socialAccountExists
    case socialIdentityAlreadyLinked
    case socialVerificationFailed
}

extension SessionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            CoreLocalization.string("Неправильна електронна адреса або пароль.")
        case .invalidInput:
            CoreLocalization.string("Перевірте введені дані й спробуйте ще раз.")
        case .invalidToken, .expired:
            CoreLocalization.string("Сеанс завершився. Увійдіть знову.")
        case .invalidResponse:
            CoreLocalization.string("Сервіс повернув неочікувану відповідь.")
        case .unavailable:
            CoreLocalization.string("Не вдалося з’єднатися із сервісом.")
        case .socialAccountExists:
            CoreLocalization.string("Ця адреса вже зареєстрована. Увійдіть звичним способом, а потім під’єднайте Apple чи Google у профілі.")
        case .socialIdentityAlreadyLinked:
            CoreLocalization.string("Цей спосіб входу вже під’єднано до іншого облікового запису.")
        case .socialVerificationFailed:
            CoreLocalization.string("Не вдалося підтвердити вхід. Спробуйте ще раз.")
        case .storage:
            CoreLocalization.string("Не вдалося безпечно зберегти сеанс.")
        }
    }
}
