import Foundation
import XCTest
@testable import BeryndaCore

private final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedTokens: AuthTokens?
    private var saveCountValue = 0
    private var failSaves = false
    private var failClears = false

    init(tokens: AuthTokens? = nil) {
        storedTokens = tokens
    }

    func load() throws -> AuthTokens? {
        lock.lock()
        defer { lock.unlock() }
        return storedTokens
    }

    func save(_ tokens: AuthTokens) throws {
        lock.lock()
        defer { lock.unlock() }
        if failSaves { throw SessionError.storage }
        storedTokens = tokens
        saveCountValue += 1
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        if failClears { throw SessionError.storage }
        storedTokens = nil
    }

    func setFailSaves(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        failSaves = value
    }

    func setFailClears(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        failClears = value
    }

    func snapshot() -> AuthTokens? {
        lock.lock()
        defer { lock.unlock() }
        return storedTokens
    }

    func saveCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return saveCountValue
    }
}

private actor AuthenticationStub: AuthenticationServing {
    let loginSession: AuthSession
    let refreshedTokens: AuthTokens
    let refreshError: SessionError?
    let logoutError: SessionError?
    let refreshDelayNanoseconds: UInt64

    private var refreshCallsValue = 0
    private var logoutCallsValue: [(String, String)] = []

    init(
        loginSession: AuthSession,
        refreshedTokens: AuthTokens,
        refreshError: SessionError? = nil,
        logoutError: SessionError? = nil,
        refreshDelayNanoseconds: UInt64 = 0
    ) {
        self.loginSession = loginSession
        self.refreshedTokens = refreshedTokens
        self.refreshError = refreshError
        self.logoutError = logoutError
        self.refreshDelayNanoseconds = refreshDelayNanoseconds
    }

    func login(email: String, password: String) async throws -> AuthSession {
        loginSession
    }

    func register(email: String, password: String, displayName: String) async throws -> RegistrationResult {
        RegistrationResult(
            id: loginSession.user.id,
            email: email,
            activation: "email_confirmation_required"
        )
    }

    func requestPasswordReset(email: String) async throws {}

    func confirmEmail(token: String) async throws -> UserProfile { loginSession.user }

    func confirmPasswordReset(uid: String, token: String, newPassword: String) async throws {}

    func refresh(refreshToken: String) async throws -> AuthTokens {
        refreshCallsValue += 1
        if refreshDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: refreshDelayNanoseconds)
        }
        if let refreshError { throw refreshError }
        return refreshedTokens
    }

    func logout(accessToken: String, refreshToken: String) async throws {
        logoutCallsValue.append((accessToken, refreshToken))
        if let logoutError { throw logoutError }
    }

    func refreshCalls() -> Int { refreshCallsValue }
    func logoutCalls() -> [(String, String)] { logoutCallsValue }

    private var accountCallTokens: [String] = []
    func accountTokens() -> [String] { accountCallTokens }

    /// Rejects the stored "old" access token the way an expired one is.
    func changePassword(currentPassword: String, newPassword: String, accessToken: String) async throws -> AuthTokens {
        accountCallTokens.append(accessToken)
        if accessToken.contains("old-access") { throw SessionError.expired }
        return try AuthTokens(access: "header.changed-access.signature", refresh: "header.changed-refresh.signature")
    }

    func deleteAccount(proof: AccountDeletionProof, accessToken: String) async throws {
        accountCallTokens.append(accessToken)
        if accessToken.contains("old-access") { throw SessionError.expired }
    }
}

final class SessionControllerTests: XCTestCase {
    func testRestoresStoredSessionWithoutNetworkCall() async throws {
        let old = try tokens("old")
        let service = try service()
        let controller = SessionController(
            tokenStore: MemoryTokenStore(tokens: old),
            authentication: service
        )

        let access = await controller.accessToken()
        let state = await controller.state()
        let refreshCalls = await service.refreshCalls()

        XCTAssertEqual(access, old.access)
        XCTAssertEqual(state, .authenticated)
        XCTAssertEqual(refreshCalls, 0)
    }

    func testSignInPersistsPairAsOneStoreValue() async throws {
        let store = MemoryTokenStore()
        let service = try service()
        let controller = SessionController(tokenStore: store, authentication: service)

        let profile = try await controller.signIn(email: "reader@example.org", password: "secret")

        XCTAssertEqual(profile.email, "reader@example.org")
        XCTAssertEqual(store.snapshot(), try tokens("login"))
        XCTAssertEqual(store.saveCount(), 1)
        let state = await controller.state()
        XCTAssertEqual(state, .authenticated)
    }

    func testConcurrentRefreshesAreCoalescedAndRotationIsSavedOnce() async throws {
        let old = try tokens("old")
        let rotated = try tokens("rotated")
        let store = MemoryTokenStore(tokens: old)
        let service = try service(
            refreshedTokens: rotated,
            refreshDelayNanoseconds: 50_000_000
        )
        let controller = SessionController(tokenStore: store, authentication: service)

        let values = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await controller.refreshAccessToken(rejectedAccessToken: old.access)
                }
            }
            var results: [String] = []
            for try await value in group { results.append(value) }
            return results
        }

        let refreshCalls = await service.refreshCalls()
        XCTAssertEqual(Set(values), Set([rotated.access]))
        XCTAssertEqual(refreshCalls, 1)
        XCTAssertEqual(store.snapshot(), rotated)
        XCTAssertEqual(store.saveCount(), 1)
    }

    func testARequestWithAnAlreadyReplacedTokenDoesNotRotateAgain() async throws {
        let current = try tokens("current")
        let service = try service()
        let controller = SessionController(
            tokenStore: MemoryTokenStore(tokens: current),
            authentication: service
        )

        let access = try await controller.refreshAccessToken(
            rejectedAccessToken: try tokens("stale").access
        )

        XCTAssertEqual(access, current.access)
        let refreshCalls = await service.refreshCalls()
        XCTAssertEqual(refreshCalls, 0)
    }

    func testExpiredRefreshClearsLocalCredentials() async throws {
        let old = try tokens("old")
        let store = MemoryTokenStore(tokens: old)
        let service = try service(refreshError: .expired)
        let controller = SessionController(tokenStore: store, authentication: service)

        do {
            _ = try await controller.refreshAccessToken(rejectedAccessToken: old.access)
            XCTFail("Expected expiry")
        } catch {
            XCTAssertEqual(error as? SessionError, .expired)
        }

        XCTAssertNil(store.snapshot())
        let access = await controller.accessToken()
        let state = await controller.state()
        XCTAssertNil(access)
        XCTAssertEqual(state, .expired)
    }

    func testTransientRefreshFailureKeepsExistingCredentials() async throws {
        let old = try tokens("old")
        let store = MemoryTokenStore(tokens: old)
        let service = try service(refreshError: .unavailable)
        let controller = SessionController(tokenStore: store, authentication: service)

        do {
            _ = try await controller.refreshAccessToken(rejectedAccessToken: old.access)
            XCTFail("Expected transport failure")
        } catch {
            XCTAssertEqual(error as? SessionError, .unavailable)
        }

        XCTAssertEqual(store.snapshot(), old)
        let state = await controller.state()
        XCTAssertEqual(state, .authenticated)
    }

    func testFailedAtomicRotationExpiresUnrecoverableLocalSession() async throws {
        let old = try tokens("old")
        let store = MemoryTokenStore(tokens: old)
        store.setFailSaves(true)
        let controller = SessionController(
            tokenStore: store,
            authentication: try service(refreshedTokens: tokens("rotated"))
        )

        do {
            _ = try await controller.refreshAccessToken(rejectedAccessToken: old.access)
            XCTFail("Expected storage failure")
        } catch {
            XCTAssertEqual(error as? SessionError, .storage)
        }

        XCTAssertNil(store.snapshot())
        let state = await controller.state()
        XCTAssertEqual(state, .expired)
    }

    func testLogoutClearsDeviceBeforeBestEffortServerRevocation() async throws {
        let old = try tokens("old")
        let store = MemoryTokenStore(tokens: old)
        let service = try service(logoutError: .unavailable)
        let controller = SessionController(tokenStore: store, authentication: service)

        try await controller.signOut()

        XCTAssertNil(store.snapshot())
        let access = await controller.accessToken()
        let state = await controller.state()
        let logoutCalls = await service.logoutCalls()
        XCTAssertNil(access)
        XCTAssertEqual(state, .anonymous)
        XCTAssertEqual(logoutCalls.count, 1)
    }

    func testLogoutReportsWhenKeychainCredentialsCouldNotBeErased() async throws {
        let old = try tokens("old")
        let store = MemoryTokenStore(tokens: old)
        store.setFailClears(true)
        let controller = SessionController(
            tokenStore: store,
            authentication: try service()
        )

        do {
            try await controller.signOut()
            XCTFail("Expected storage failure")
        } catch {
            XCTAssertEqual(error as? SessionError, .storage)
        }

        XCTAssertEqual(store.snapshot(), old)
        let memoryAccess = await controller.accessToken()
        XCTAssertNil(memoryAccess)
    }

    func testPasswordChangeRefreshesOnceAndKeepsTheFreshPair() async throws {
        let store = MemoryTokenStore(tokens: try tokens("old"))
        let service = try service()
        let controller = SessionController(tokenStore: store, authentication: service)

        try await controller.changePassword(currentPassword: "old-secret", newPassword: "new-secret-1")

        let used = await service.accountTokens()
        XCTAssertEqual(used, ["header.old-access.signature", "header.refreshed-access.signature"])
        XCTAssertEqual(store.snapshot(), try tokens("changed"))
        let state = await controller.state()
        XCTAssertEqual(state, .authenticated)
        let logouts = await service.logoutCalls()
        XCTAssertTrue(logouts.isEmpty)
    }

    func testDeletionForgetsTheSessionWithoutALogoutCall() async throws {
        let store = MemoryTokenStore(tokens: try tokens("login"))
        let service = try service()
        let controller = SessionController(tokenStore: store, authentication: service)

        try await controller.deleteAccount(proof: .password("secret"))

        XCTAssertNil(store.snapshot())
        let state = await controller.state()
        XCTAssertEqual(state, .anonymous)
        let logouts = await service.logoutCalls()
        XCTAssertTrue(logouts.isEmpty, "The server already revoked every token")
    }

    func testTokenDescriptionsNeverExposeCredentials() throws {
        let value = try tokens("highly-secret")

        XCTAssertEqual(String(describing: value), "AuthTokens(<redacted>)")
        XCTAssertEqual(String(reflecting: value), "AuthTokens(<redacted>)")
        XCTAssertFalse(String(reflecting: value).contains(value.access))
        XCTAssertFalse(String(reflecting: value).contains(value.refresh))
    }

    private func service(
        refreshedTokens: AuthTokens? = nil,
        refreshError: SessionError? = nil,
        logoutError: SessionError? = nil,
        refreshDelayNanoseconds: UInt64 = 0
    ) throws -> AuthenticationStub {
        let loginTokens = try tokens("login")
        let profile = UserProfile(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            email: "reader@example.org",
            displayName: "Reader"
        )
        let effectiveRefreshedTokens: AuthTokens
        if let refreshedTokens {
            effectiveRefreshedTokens = refreshedTokens
        } else {
            effectiveRefreshedTokens = try tokens("refreshed")
        }
        return AuthenticationStub(
            loginSession: AuthSession(tokens: loginTokens, user: profile),
            refreshedTokens: effectiveRefreshedTokens,
            refreshError: refreshError,
            logoutError: logoutError,
            refreshDelayNanoseconds: refreshDelayNanoseconds
        )
    }

    private func tokens(_ marker: String) throws -> AuthTokens {
        try AuthTokens(
            access: "header.\(marker)-access.signature",
            refresh: "header.\(marker)-refresh.signature"
        )
    }
}
