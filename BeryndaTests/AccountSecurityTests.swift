import Foundation
import XCTest
import BeryndaCore
@testable import Berynda

/// «Безпека»: the password form's own checks, and how each refusal of the
/// password-change and deletion endpoints reaches the screen.
@MainActor
final class AccountSecurityTests: XCTestCase {
    private static let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    func testPasswordFormCatchesMistakesBeforeSending() async throws {
        let model = AccountSecurityViewModel(account: try await signedInAccount().account)
        model.currentPassword = "password123"

        model.newPassword = "short"
        XCTAssertEqual(model.passwordFormProblem, "Новий пароль має містити щонайменше 8 символів.")
        XCTAssertFalse(model.canChangePassword)

        model.newPassword = "a-new-password"
        model.repeatedPassword = "a-new-passwort"
        XCTAssertEqual(model.passwordFormProblem, "Паролі не збігаються.")
        XCTAssertFalse(model.canChangePassword)

        model.newPassword = "password123"
        model.repeatedPassword = "password123"
        XCTAssertEqual(model.passwordFormProblem, "Новий пароль має відрізнятися від поточного.")

        model.newPassword = "a-new-password"
        model.repeatedPassword = "a-new-password"
        XCTAssertNil(model.passwordFormProblem)
        XCTAssertTrue(model.canChangePassword)
    }

    func testPasswordChangeSucceedsAndClearsTheForm() async throws {
        let fixture = try await signedInAccount()
        let model = AccountSecurityViewModel(account: fixture.account)
        model.currentPassword = "password123"
        model.newPassword = "a-new-password"
        model.repeatedPassword = "a-new-password"

        await model.changePassword()

        XCTAssertTrue(model.passwordChanged)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.currentPassword, "")
        XCTAssertEqual(fixture.account.state, .authenticated)
    }

    func testWrongCurrentPasswordIsSaidPlainly() async throws {
        let model = AccountSecurityViewModel(account: try await signedInAccount().account)
        model.currentPassword = "not-my-password"
        model.newPassword = "a-new-password"
        model.repeatedPassword = "a-new-password"

        await model.changePassword()

        XCTAssertFalse(model.passwordChanged)
        XCTAssertEqual(model.errorMessage, "Поточний пароль неправильний.")
    }

    func testServerPasswordRulesAppearUnderTheNewPassword() async throws {
        let refusing = RefusingAuthentication(failure: AccountSecurityError.passwordRejected(["Цей пароль надто поширений."]))
        let model = AccountSecurityViewModel(account: try await signedInAccount(authentication: refusing).account)
        model.currentPassword = "password123"
        model.newPassword = "qwertyuiop"
        model.repeatedPassword = "qwertyuiop"

        await model.changePassword()

        XCTAssertEqual(model.newPasswordMessages, ["Цей пароль надто поширений."])
        XCTAssertNil(model.errorMessage)
    }

    func testAnAccountWithoutAPasswordIsOfferedTheSetupEmail() async throws {
        let refusing = RefusingAuthentication(failure: AccountSecurityError.noPassword)
        let model = AccountSecurityViewModel(account: try await signedInAccount(authentication: refusing).account)
        XCTAssertFalse(model.needsPasswordSetup)
        model.currentPassword = "anything-at-all"
        model.newPassword = "a-new-password"
        model.repeatedPassword = "a-new-password"

        await model.changePassword()

        XCTAssertTrue(model.needsPasswordSetup)
        await model.sendPasswordSetupEmail()
        XCTAssertEqual(model.setupEmailSentTo, "reader@example.org")
    }

    func testAppleLinkedAccountsAreSentToApple() async throws {
        let refusing = RefusingAuthentication(failure: AccountSecurityError.appleReauthenticationRequired)
        let model = AccountSecurityViewModel(account: try await signedInAccount(authentication: refusing).account)
        XCTAssertEqual(model.deletionMethods, [.password])
        model.deletionPassword = "password123"

        let deleted = await model.deleteWithPassword()

        XCTAssertFalse(deleted)
        XCTAssertEqual(model.deletionMethods, [.apple])
        XCTAssertEqual(model.deletionPassword, "")
        XCTAssertNotNil(model.errorMessage)
    }

    func testReauthenticationRequiredOffersTheServersMethods() async throws {
        let refusing = RefusingAuthentication(failure: AccountSecurityError.reauthenticationRequired([.google]))
        let model = AccountSecurityViewModel(account: try await signedInAccount(authentication: refusing).account)
        model.deletionPassword = "password123"

        _ = await model.deleteWithPassword()

        XCTAssertEqual(model.deletionMethods, [.google])
    }

    func testWrongPasswordKeepsTheAccount() async throws {
        let fixture = try await signedInAccount()
        let model = AccountSecurityViewModel(account: fixture.account)
        model.deletionPassword = "not-my-password"

        let deleted = await model.deleteWithPassword()

        XCTAssertFalse(deleted)
        XCTAssertEqual(model.errorMessage, "Поточний пароль неправильний.")
        XCTAssertEqual(fixture.account.state, .authenticated)
    }

    func testDeletionLeavesNothingOfTheAccountOnTheDevice() async throws {
        let fixture = try await signedInAccount()
        await fixture.positions.save(page: 3, totalPages: 12, for: Self.fileID)
        let model = AccountSecurityViewModel(account: fixture.account)
        model.deletionPassword = "password123"

        let deleted = await model.deleteWithPassword()

        XCTAssertTrue(deleted)
        XCTAssertEqual(fixture.account.state, .anonymous)
        XCTAssertNil(fixture.account.profile)
        let position = await fixture.positions.position(for: Self.fileID)
        XCTAssertNil(position)
        let state = await fixture.session.state()
        XCTAssertEqual(state, .anonymous)
    }

    func testDeletionWithAProviderUsesAReauthenticationChallenge() async throws {
        let refusing = RefusingAuthentication(failure: nil)
        let fixture = try await signedInAccount(authentication: refusing)
        let model = AccountSecurityViewModel(account: fixture.account)

        let deleted = await model.deleteWithSocial(.apple) { challenge in
            SocialReauthentication(
                provider: .apple,
                challengeID: challenge.challengeID,
                identityToken: "apple.identity.token",
                authorizationCode: "one-time-code"
            )
        }

        XCTAssertTrue(deleted)
        let proofs = await refusing.deletionProofs
        XCTAssertEqual(proofs, ["apple:one-time-code"])
    }

    // MARK: - Fixtures

    private struct Fixture {
        let account: AccountViewModel
        let session: SessionController
        let positions: LocalReadingPositionStore
    }

    private func signedInAccount(
        authentication: any AuthenticationServing = UITestAuthenticationService()
    ) async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccountSecurityTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let positions = LocalReadingPositionStore(
            directory: directory.appendingPathComponent("positions", isDirectory: true)
        )
        let recentlyViewed = RecentlyViewedStore(
            directory: directory.appendingPathComponent("recently-viewed", isDirectory: true)
        )
        let session = SessionController(tokenStore: UITestTokenStore(), authentication: authentication)
        let account = AccountViewModel(
            session: session,
            authentication: authentication,
            repository: UITestAccountRepository(),
            localPositions: positions,
            recentlyViewed: recentlyViewed
        )
        let signedIn = await account.signIn(email: "reader@example.org", password: "password123")
        XCTAssertTrue(signedIn, account.errorMessage ?? "Sign-in failed")
        return Fixture(account: account, session: session, positions: positions)
    }
}

/// Signs in like the UI-test service, then answers every account action with
/// one chosen refusal (or success when `failure` is nil).
private actor RefusingAuthentication: AuthenticationServing {
    let failure: Error?
    private(set) var deletionProofs: [String] = []

    init(failure: Error?) {
        self.failure = failure
    }

    func login(email: String, password: String) async throws -> AuthSession {
        AuthSession(
            tokens: try AuthTokens(access: "header.access.signature", refresh: "header.refresh.signature"),
            user: UserProfile(
                id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
                email: email,
                displayName: "Тестовий читач"
            )
        )
    }

    func register(email: String, password: String, displayName: String) async throws -> RegistrationResult {
        throw SessionError.unavailable
    }

    func confirmEmail(token: String) async throws -> UserProfile { throw SessionError.unavailable }
    func requestPasswordReset(email: String) async throws {}
    func confirmPasswordReset(uid: String, token: String, newPassword: String) async throws {}
    func refresh(refreshToken: String) async throws -> AuthTokens { throw SessionError.expired }
    func logout(accessToken: String, refreshToken: String) async throws {}

    func reauthenticationChallenge(provider: SocialProvider, accessToken: String) async throws -> SocialChallenge {
        try JSONDecoder().decode(
            SocialChallenge.self,
            from: Data(#"{"challenge_id":"12345678-1234-1234-1234-123456789012","nonce":"n","expires_in":300}"#.utf8)
        )
    }

    func changePassword(currentPassword: String, newPassword: String, accessToken: String) async throws -> AuthTokens {
        if let failure { throw failure }
        return try AuthTokens(access: "header.access-2.signature", refresh: "header.refresh-2.signature")
    }

    func deleteAccount(proof: AccountDeletionProof, accessToken: String) async throws {
        if let failure { throw failure }
        if case let .social(credential) = proof {
            deletionProofs.append("\(credential.provider.rawValue):\(credential.authorizationCode ?? "")")
        }
    }
}
