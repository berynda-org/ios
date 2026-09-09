import Foundation
import XCTest
import BeryndaCore
@testable import Berynda

/// Privacy behaviour of the account layer: on-device reading history must not
/// outlive the account it belongs to, and the interface-language preference
/// must follow the server profile rather than overwrite it.
@MainActor
final class AccountPrivacyTests: XCTestCase {
    private static let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    func testSigningOutClearsReadingPositionsAndRecentlyViewedWorks() async throws {
        let fixture = try await makeSignedInAccount()
        try await seedHistory(fixture)

        await fixture.account.signOut()

        XCTAssertEqual(fixture.account.state, .anonymous)
        XCTAssertNil(fixture.account.profile)
        let position = await fixture.positions.position(for: Self.fileID)
        XCTAssertNil(position, "Reading positions must not leak to the next account")
        let recent = await fixture.recentlyViewed.recent()
        XCTAssertTrue(recent.isEmpty, "Recently viewed works must not leak to the next account")
    }

    func testTurningReadingHistoryOffClearsReadingPositionsAndRecentlyViewedWorks() async throws {
        let fixture = try await makeSignedInAccount()
        try await seedHistory(fixture)

        let saved = await fixture.account.updateProfile(
            ProfileUpdate(privacySettings: ["reading_history_enabled": false])
        )

        XCTAssertTrue(saved)
        XCTAssertEqual(fixture.account.state, .authenticated)
        XCTAssertEqual(fixture.account.profile?.readingHistoryEnabled, false)
        let position = await fixture.positions.position(for: Self.fileID)
        XCTAssertNil(position, "Turning history off must drop stored positions")
        let recent = await fixture.recentlyViewed.recent()
        XCTAssertTrue(recent.isEmpty, "Turning history off must empty the recently-viewed shelf")
    }

    func testLoadedProfileSeedsTheInterfaceLanguagePreference() async throws {
        let key = AccountViewModel.interfaceLanguageKey
        XCTAssertEqual(key, "ui.language")
        let previous = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        addTeardownBlock {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let fixture = try await makeSignedInAccount(repository: EnglishProfileRepository())
        await fixture.account.loadProfile()

        XCTAssertEqual(fixture.account.profile?.uiLanguage, "en")
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "en")
    }

    // MARK: - Fixtures

    private struct Fixture {
        let account: AccountViewModel
        let positions: LocalReadingPositionStore
        let recentlyViewed: RecentlyViewedStore
    }

    private func makeSignedInAccount(
        repository: any AccountRepository = UITestAccountRepository()
    ) async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccountPrivacyTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let positions = LocalReadingPositionStore(
            directory: directory.appendingPathComponent("positions", isDirectory: true)
        )
        let recentlyViewed = RecentlyViewedStore(
            directory: directory.appendingPathComponent("recently-viewed", isDirectory: true)
        )

        let authentication = UITestAuthenticationService()
        let session = SessionController(
            tokenStore: UITestTokenStore(),
            authentication: authentication
        )
        let account = AccountViewModel(
            session: session,
            authentication: authentication,
            repository: repository,
            localPositions: positions,
            recentlyViewed: recentlyViewed
        )
        let signedIn = await account.signIn(email: "reader@example.org", password: "password123")
        XCTAssertTrue(signedIn, account.errorMessage ?? "Sign-in failed")
        XCTAssertEqual(account.state, .authenticated)

        return Fixture(account: account, positions: positions, recentlyViewed: recentlyViewed)
    }

    private func seedHistory(_ fixture: Fixture) async throws {
        await fixture.positions.save(page: 3, totalPages: 12, for: Self.fileID)
        await fixture.recentlyViewed.record(try Self.viewedWork())

        let position = await fixture.positions.position(for: Self.fileID)
        XCTAssertEqual(position?.page, 3, "Fixture should start with a stored position")
        let recent = await fixture.recentlyViewed.recent()
        XCTAssertEqual(recent.map(\.slug), ["lisova-pisnia"], "Fixture should start with a viewed work")
    }

    private static func viewedWork() throws -> WorkSummary {
        let json = """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "slug": "lisova-pisnia",
          "title": "Лісова пісня",
          "subtitle": null,
          "language": "uk",
          "first_published_year": 1912,
          "authors": [{"id": "88888888-8888-8888-8888-888888888888", "display_name": "Леся Українка"}],
          "editions_count": 1,
          "has_text_file": true,
          "cover_image_url": null,
          "cover_tone": null,
          "cover_variant": null,
          "cover_glyph": null
        }
        """
        return try JSONDecoder().decode(WorkSummary.self, from: Data(json.utf8))
    }
}

/// An account whose server-side preference is English, so the test can tell a
/// seeded value from the picker's "uk" default.
private struct EnglishProfileRepository: AccountRepository {
    func profile() async throws -> UserProfile {
        let json = """
        {
          "id": "99999999-9999-9999-9999-999999999999",
          "email": "reader@example.org",
          "display_name": "Test reader",
          "ui_language": "en",
          "privacy_settings": {}
        }
        """
        return try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
    }

    func updateProfile(_ update: ProfileUpdate) async throws -> UserProfile {
        try await profile()
    }
}
