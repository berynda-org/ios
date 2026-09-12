import Foundation

public struct AuthTokens: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let access: String
    public let refresh: String

    public init(access: String, refresh: String) throws {
        guard Self.isValidJWT(access), Self.isValidJWT(refresh) else {
            throw SessionError.invalidToken
        }
        self.access = access
        self.refresh = refresh
    }

    public var description: String { "AuthTokens(<redacted>)" }
    public var debugDescription: String { description }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let access = try container.decode(String.self, forKey: .access)
        let refresh = try container.decode(String.self, forKey: .refresh)
        guard Self.isValidJWT(access), Self.isValidJWT(refresh) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid token representation")
            )
        }
        self.access = access
        self.refresh = refresh
    }

    static func isValidJWT(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 16_384 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
            && value.split(separator: ".", omittingEmptySubsequences: false).count == 3
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

    public init(
        id: UUID,
        email: String,
        displayName: String?,
        bio: String? = nil,
        institutionName: String? = nil,
        uiLanguage: String = "uk",
        privacySettings: [String: Bool] = [:]
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.bio = bio
        self.institutionName = institutionName
        self.uiLanguage = uiLanguage
        self.privacySettings = privacySettings
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
    }

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case bio
        case institutionName = "institution_name"
        case uiLanguage = "ui_language"
        case privacySettings = "privacy_settings"
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
            "Неправильна електронна адреса або пароль."
        case .invalidInput:
            "Перевірте введені дані й спробуйте ще раз."
        case .invalidToken, .expired:
            "Сеанс завершився. Увійдіть знову."
        case .invalidResponse:
            "Сервіс повернув неочікувану відповідь."
        case .unavailable:
            "Не вдалося з’єднатися із сервісом."
        case .socialAccountExists:
            "Ця адреса вже зареєстрована. Увійдіть звичним способом, а потім під’єднайте Apple чи Google у профілі."
        case .socialIdentityAlreadyLinked:
            "Цей спосіб входу вже під’єднано до іншого облікового запису."
        case .socialVerificationFailed:
            "Не вдалося підтвердити вхід. Спробуйте ще раз."
        case .storage:
            "Не вдалося безпечно зберегти сеанс."
        }
    }
}
