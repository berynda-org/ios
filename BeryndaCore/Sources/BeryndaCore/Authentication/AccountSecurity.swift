import Foundation

/// Ways the server accepts to confirm it is really the account holder, as
/// named in a 409's `details.methods`: `password`, `apple`, `google`.
public enum ReauthenticationMethod: String, Sendable, Equatable, CaseIterable {
    case password
    case apple
    case google

    public var socialProvider: SocialProvider? {
        switch self {
        case .password: nil
        case .apple: .apple
        case .google: .google
        }
    }

    /// The methods offered for deleting an account. An Apple-linked account
    /// must use Apple — the server needs a fresh authorization code to revoke
    /// the app's Apple tokens — so nothing else is offered to it.
    public static func available(hasPassword: Bool, socialProviders: [String]) -> [ReauthenticationMethod] {
        let linked = socialProviders.compactMap { ReauthenticationMethod(rawValue: $0.lowercased()) }
            .filter { $0 != .password }
        if linked.contains(.apple) { return [.apple] }
        var methods: [ReauthenticationMethod] = hasPassword ? [.password] : []
        for method in [ReauthenticationMethod.google] where linked.contains(method) {
            methods.append(method)
        }
        return methods
    }
}

/// A fresh proof of identity from Apple or Google for an account action.
/// `authorizationCode` is required for Apple: the server exchanges it to
/// revoke the app's Apple tokens when the account goes.
public struct SocialReauthentication: Encodable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let provider: SocialProvider
    public let challengeID: UUID
    public let identityToken: String
    public let authorizationCode: String?

    public init(provider: SocialProvider, challengeID: UUID, identityToken: String, authorizationCode: String?) {
        self.provider = provider
        self.challengeID = challengeID
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
    }

    public var description: String { "SocialReauthentication(<redacted>)" }
    public var debugDescription: String { description }

    enum CodingKeys: String, CodingKey {
        case provider
        case challengeID = "challenge_id"
        case identityToken = "identity_token"
        case authorizationCode = "authorization_code"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(challengeID, forKey: .challengeID)
        try container.encode(identityToken, forKey: .identityToken)
        try container.encodeIfPresent(authorizationCode, forKey: .authorizationCode)
    }
}

/// What `DELETE auth/me/` is sent to prove the request comes from the owner.
public enum AccountDeletionProof: Sendable {
    case password(String)
    case social(SocialReauthentication)
}

/// The refusals of the password-change and account-deletion endpoints, by
/// their stable error codes.
public enum AccountSecurityError: Error, Equatable, Sendable {
    case invalidCurrentPassword
    /// The new password failed the server's validators; the messages are
    /// the server's own, shown under the field.
    case passwordRejected([String])
    /// An Apple/Google-only account: a password is set through the reset email.
    case noPassword
    /// Confirm with one of these methods.
    case reauthenticationRequired([ReauthenticationMethod])
    case appleReauthenticationRequired
    case socialReauthenticationFailed
    case socialProviderUnavailable
    case permissionDenied
    case rateLimited
}

extension AccountSecurityError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCurrentPassword:
            "Поточний пароль неправильний."
        case let .passwordRejected(messages):
            messages.isEmpty ? "Новий пароль не підходить. Оберіть інший." : messages.joined(separator: " ")
        case .noPassword:
            "Для цього облікового запису пароль ще не встановлено."
        case .reauthenticationRequired:
            "Підтвердьте, що це ви, щоб продовжити."
        case .appleReauthenticationRequired:
            "Цей обліковий запис пов’язано з Apple. Підтвердьте видалення через Apple."
        case .socialReauthenticationFailed:
            "Не вдалося підтвердити вхід. Спробуйте ще раз."
        case .socialProviderUnavailable:
            "Сервіс входу зараз недоступний. Спробуйте пізніше."
        case .permissionDenied:
            "Обліковий запис працівника не можна видалити із застосунку."
        case .rateLimited:
            "Забагато спроб. Зачекайте трохи й спробуйте знову."
        }
    }
}

/// `{"error": {"code", "message", "details"}}`, the envelope every refusal of
/// these endpoints uses.
struct AccountProblemResponse: Decodable {
    let error: Problem

    struct Problem: Decodable {
        let code: String
        let details: Details?
    }

    struct Details: Decodable {
        let newPassword: [String]?
        let methods: [String]?

        enum CodingKeys: String, CodingKey {
            case methods
            case newPassword = "new_password"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            newPassword = (try? container.decode([String].self, forKey: .newPassword))
                ?? (try? container.decode(String.self, forKey: .newPassword)).map { [$0] }
            methods = try? container.decode([String].self, forKey: .methods)
        }
    }

    /// The typed error for a refusal, or `nil` when the code is not one these
    /// endpoints define (the caller then falls back on the status).
    var accountError: AccountSecurityError? {
        let methods = (error.details?.methods ?? []).compactMap { ReauthenticationMethod(rawValue: $0.lowercased()) }
        switch error.code {
        case "INVALID_CURRENT_PASSWORD": return .invalidCurrentPassword
        case "VALIDATION_ERROR":
            guard let messages = error.details?.newPassword else { return nil }
            return .passwordRejected(messages)
        case "NO_PASSWORD": return .noPassword
        case "APPLE_REAUTH_REQUIRED": return .appleReauthenticationRequired
        case "REAUTH_REQUIRED": return .reauthenticationRequired(methods)
        case "SOCIAL_REAUTH_FAILED": return .socialReauthenticationFailed
        case "SOCIAL_PROVIDER_UNAVAILABLE": return .socialProviderUnavailable
        case "PERMISSION_DENIED": return .permissionDenied
        default: return nil
        }
    }
}
