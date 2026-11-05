import Foundation

public protocol TokenStore: Sendable {
    func load() throws -> AuthTokens?
    func save(_ tokens: AuthTokens) throws
    func clear() throws
}

public protocol AuthorizationSession: Sendable {
    func accessToken() async -> String?
    func refreshAccessToken(rejectedAccessToken: String) async throws -> String
}
