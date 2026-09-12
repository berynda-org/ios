import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol AuthenticationServing: Sendable {
    func socialConfiguration() async throws -> SocialProviderConfiguration
    func socialChallenge(provider: SocialProvider, accessToken: String?) async throws -> SocialChallenge
    func socialLogin(_ credential: SocialCredential) async throws -> AuthSession
    func linkSocialIdentity(_ credential: SocialCredential, accessToken: String) async throws -> UserProfile
    func login(email: String, password: String) async throws -> AuthSession
    func register(email: String, password: String, displayName: String) async throws -> RegistrationResult
    func confirmEmail(token: String) async throws -> UserProfile
    func requestPasswordReset(email: String) async throws
    func confirmPasswordReset(
        uid: String,
        token: String,
        newPassword: String
    ) async throws
    func refresh(refreshToken: String) async throws -> AuthTokens
    func logout(accessToken: String, refreshToken: String) async throws
}

public extension AuthenticationServing {
    func socialConfiguration() async throws -> SocialProviderConfiguration { .disabled }
    func socialChallenge(provider: SocialProvider, accessToken: String?) async throws -> SocialChallenge {
        throw SessionError.unavailable
    }
    func socialLogin(_ credential: SocialCredential) async throws -> AuthSession { throw SessionError.unavailable }
    func linkSocialIdentity(_ credential: SocialCredential, accessToken: String) async throws -> UserProfile {
        throw SessionError.unavailable
    }
}

public actor LiveAuthenticationService: AuthenticationServing {
    private let baseURL: URL
    private let transport: any HTTPTransport
    private let language: @Sendable () -> String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        baseURL: URL,
        transport: any HTTPTransport = URLSessionTransport(),
        language: @escaping @Sendable () -> String = { "uk" }
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.language = language
    }

    public func socialConfiguration() async throws -> SocialProviderConfiguration {
        try await get(path: "auth/social/config/")
    }

    public func socialChallenge(provider: SocialProvider, accessToken: String?) async throws -> SocialChallenge {
        try await post(path: "auth/social/challenge/",
                       body: SocialChallengeBody(provider: provider, linkAccount: accessToken != nil),
                       bearerToken: accessToken, unauthorizedError: .expired)
    }

    public func socialLogin(_ credential: SocialCredential) async throws -> AuthSession {
        let response: LoginResponse = try await post(path: "auth/social/login/", body: credential,
                                                    bearerToken: nil, unauthorizedError: .socialVerificationFailed)
        return AuthSession(tokens: try AuthTokens(access: response.access, refresh: response.refresh), user: response.user)
    }

    public func linkSocialIdentity(_ credential: SocialCredential, accessToken: String) async throws -> UserProfile {
        try await post(path: "auth/social/link/", body: credential,
                       bearerToken: accessToken, unauthorizedError: .expired)
    }

    public func login(email: String, password: String) async throws -> AuthSession {
        let body = LoginBody(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        let response: LoginResponse = try await post(
            path: "auth/login/",
            body: body,
            bearerToken: nil,
            unauthorizedError: .invalidCredentials
        )
        let tokens = try AuthTokens(access: response.access, refresh: response.refresh)
        return AuthSession(tokens: tokens, user: response.user)
    }

    public func register(
        email: String,
        password: String,
        displayName: String
    ) async throws -> RegistrationResult {
        try await post(
            path: "auth/register/",
            body: RegistrationBody(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            bearerToken: nil,
            unauthorizedError: .invalidInput
        )
    }

    public func requestPasswordReset(email: String) async throws {
        let _: StatusResponse = try await post(
            path: "auth/password-reset/",
            body: PasswordResetBody(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            bearerToken: nil,
            unauthorizedError: .invalidInput
        )
    }

    public func confirmEmail(token: String) async throws -> UserProfile {
        guard Self.isSafeLinkValue(token, maximumLength: 4_096) else {
            throw SessionError.invalidInput
        }
        return try await get(path: "auth/confirm-email/\(token)/")
    }

    public func confirmPasswordReset(
        uid: String,
        token: String,
        newPassword: String
    ) async throws {
        guard Self.isSafeLinkValue(uid, maximumLength: 512),
              Self.isSafeLinkValue(token, maximumLength: 2_048),
              newPassword.count >= 8
        else { throw SessionError.invalidInput }
        let _: StatusResponse = try await post(
            path: "auth/password-reset/confirm/",
            body: PasswordResetConfirmationBody(
                uid: uid,
                token: token,
                newPassword: newPassword,
                newPasswordConfirm: newPassword
            ),
            bearerToken: nil,
            unauthorizedError: .invalidInput
        )
    }

    public func refresh(refreshToken: String) async throws -> AuthTokens {
        guard AuthTokens.isValidJWT(refreshToken) else { throw SessionError.invalidToken }
        let response: RefreshResponse = try await post(
            path: "auth/token/refresh/",
            body: RefreshBody(refresh: refreshToken),
            bearerToken: nil,
            unauthorizedError: .expired
        )
        return try AuthTokens(access: response.access, refresh: response.refresh)
    }

    public func logout(accessToken: String, refreshToken: String) async throws {
        guard AuthTokens.isValidJWT(accessToken), AuthTokens.isValidJWT(refreshToken) else {
            throw SessionError.invalidToken
        }
        let _: EmptyResponse = try await post(
            path: "auth/logout/",
            body: RefreshBody(refresh: refreshToken),
            bearerToken: accessToken,
            unauthorizedError: .expired,
            acceptsEmptyResponse: true
        )
    }

    private func get<Response: Decodable>(path: String) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw SessionError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(language(), forHTTPHeaderField: "Accept-Language")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")

        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await transport.data(for: request, maximumBytes: 1 * 1_024 * 1_024)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw SessionError.unavailable
        }
        switch http.statusCode {
        case 200..<300:
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?
                .split(separator: ";", maxSplits: 1)
                .first
                .map { String($0).lowercased() }
            guard contentType == "application/json" || contentType?.hasSuffix("+json") == true,
                  let response = try? decoder.decode(Response.self, from: data)
            else { throw SessionError.invalidResponse }
            return response
        case 400, 401, 404, 409, 422:
            throw SessionError.invalidInput
        default:
            throw SessionError.unavailable
        }
    }

    private static func isSafeLinkValue(_ value: String, maximumLength: Int) -> Bool {
        guard !value.isEmpty, value.count <= maximumLength else { return false }
        return !value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
                || $0 == "/" || $0 == "?" || $0 == "#"
        }
    }

    private func post<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        bearerToken: String?,
        unauthorizedError: SessionError,
        acceptsEmptyResponse: Bool = false
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw SessionError.invalidResponse
        }

        let requestData: Data
        do {
            requestData = try encoder.encode(body)
        } catch {
            throw SessionError.invalidResponse
        }
        guard requestData.count <= 64 * 1_024 else { throw SessionError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = requestData
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(language(), forHTTPHeaderField: "Accept-Language")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await transport.data(for: request, maximumBytes: 1 * 1_024 * 1_024)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw SessionError.unavailable
        }

        if !(200..<300).contains(http.statusCode),
           let problem = try? decoder.decode(SocialErrorResponse.self, from: data) {
            switch problem.error.code {
            case "SOCIAL_ACCOUNT_EXISTS": throw SessionError.socialAccountExists
            case "SOCIAL_IDENTITY_ALREADY_LINKED": throw SessionError.socialIdentityAlreadyLinked
            case "SOCIAL_CREDENTIALS_INVALID", "SOCIAL_VERIFIED_EMAIL_REQUIRED":
                throw SessionError.socialVerificationFailed
            default: break
            }
        }
        switch http.statusCode {
        case 200..<300:
            if acceptsEmptyResponse, data.isEmpty, let empty = EmptyResponse() as? Response {
                return empty
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?
                .split(separator: ";", maxSplits: 1)
                .first
                .map { String($0).lowercased() }
            guard contentType == "application/json" || contentType?.hasSuffix("+json") == true else {
                throw SessionError.invalidResponse
            }
            do {
                return try decoder.decode(Response.self, from: data)
            } catch let error as SessionError {
                throw error
            } catch {
                throw SessionError.invalidResponse
            }
        case 401:
            throw unauthorizedError
        case 400, 409, 422:
            throw SessionError.invalidInput
        default:
            throw SessionError.unavailable
        }
    }
}

private struct LoginBody: Encodable {
    let email: String
    let password: String
}

private struct RegistrationBody: Encodable {
    let email: String
    let password: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case email, password
        case displayName = "display_name"
    }
}

private struct PasswordResetBody: Encodable {
    let email: String
}

private struct PasswordResetConfirmationBody: Encodable {
    let uid: String
    let token: String
    let newPassword: String
    let newPasswordConfirm: String

    enum CodingKeys: String, CodingKey {
        case uid, token
        case newPassword = "new_password"
        case newPasswordConfirm = "new_password_confirm"
    }
}

private struct RefreshBody: Encodable {
    let refresh: String
}

private struct LoginResponse: Decodable {
    let access: String
    let refresh: String
    let user: UserProfile
}

private struct RefreshResponse: Decodable {
    let access: String
    let refresh: String
}

private struct EmptyResponse: Decodable {
    init() {}
}

private struct StatusResponse: Decodable {
    let status: String
}

private struct SocialChallengeBody: Encodable {
    let provider: SocialProvider
    let linkAccount: Bool
    enum CodingKeys: String, CodingKey { case provider, linkAccount = "link_account" }
}
private struct SocialErrorResponse: Decodable {
    let error: Problem
    struct Problem: Decodable { let code: String }
}
