import Foundation

public protocol AccountRepository: Sendable {
    func profile() async throws -> UserProfile
    func updateProfile(_ update: ProfileUpdate) async throws -> UserProfile
}

public struct ProfileUpdate: Encodable, Sendable, Equatable {
    public let displayName: String?
    public let bio: String?
    public let institutionName: String?
    public let uiLanguage: String?
    public let privacySettings: [String: Bool]?

    public init(
        displayName: String? = nil,
        bio: String? = nil,
        institutionName: String? = nil,
        uiLanguage: String? = nil,
        privacySettings: [String: Bool]? = nil
    ) {
        self.displayName = displayName
        self.bio = bio
        self.institutionName = institutionName
        self.uiLanguage = uiLanguage
        self.privacySettings = privacySettings
    }

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case bio
        case institutionName = "institution_name"
        case uiLanguage = "ui_language"
        case privacySettings = "privacy_settings"
    }
}

public struct LiveAccountRepository: AccountRepository {
    private let client: BeryndaAPIClient

    public init(client: BeryndaAPIClient) {
        self.client = client
    }

    public func profile() async throws -> UserProfile {
        try await client.request(.accountProfile)
    }

    public func updateProfile(_ update: ProfileUpdate) async throws -> UserProfile {
        try await client.request(.accountProfile, method: .patch, body: update)
    }
}
