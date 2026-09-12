import Foundation

public enum SocialProvider: String, Codable, Sendable { case apple, google }

public struct SocialProviderConfiguration: Decodable, Equatable, Sendable {
    public let appleEnabled: Bool
    public let googleEnabled: Bool
    public let googleIOSClientID: String?
    public let googleServerClientID: String?
    public static let disabled = Self(appleEnabled: false, googleEnabled: false,
                                     googleIOSClientID: nil, googleServerClientID: nil)
    enum CodingKeys: String, CodingKey {
        case appleEnabled = "apple_enabled", googleEnabled = "google_enabled"
        case googleIOSClientID = "google_ios_client_id", googleServerClientID = "google_server_client_id"
    }
}

public struct SocialChallenge: Decodable, Sendable {
    public let challengeID: UUID
    public let nonce: String
    public let expiresIn: Int
    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id", nonce, expiresIn = "expires_in"
    }
}

public struct SocialCredential: Encodable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let provider: SocialProvider
    public let challengeID: UUID
    public let identityToken: String
    public let displayName: String
    public init(provider: SocialProvider, challengeID: UUID, identityToken: String, displayName: String = "") {
        self.provider = provider; self.challengeID = challengeID
        self.identityToken = identityToken; self.displayName = displayName
    }
    public var description: String { "SocialCredential(<redacted>)" }
    public var debugDescription: String { description }
    enum CodingKeys: String, CodingKey {
        case provider, challengeID = "challenge_id", identityToken = "identity_token", displayName = "display_name"
    }
}
