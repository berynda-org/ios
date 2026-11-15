import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import BeryndaCore

// The opaque bearer-token contract: the server's docs/OPAQUE_TOKENS.md.

private let opaqueBody = String(repeating: "A", count: 21) + "-_" + String(repeating: "z", count: 20)
private func opaqueAccess(_ marker: Character = "a") -> String {
    "bat_" + String(repeating: marker, count: 43)
}
private func opaqueRefresh(_ marker: Character = "r") -> String {
    "brt_" + String(repeating: marker, count: 43)
}
private let legacyAccess = "eyJhbGciOiJIUzI1NiJ9.eyJ0b2tlbl90eXBlIjoiYWNjZXNzIn0.c2lnbmF0dXJl"
private let legacyRefresh = "eyJhbGciOiJIUzI1NiJ9.eyJ0b2tlbl90eXBlIjoicmVmcmVzaCJ9.c2lnbmF0dXJl"
private let baseURL = URL(string: "https://api.example.test/api/v1/")!
private let userID = "11111111-1111-1111-1111-111111111111"

private struct ScriptedResponse: Sendable {
    let status: Int
    let body: String

    static func json(_ body: String, status: Int = 200) -> ScriptedResponse {
        ScriptedResponse(status: status, body: body)
    }
}

private struct SeenRequest: Sendable {
    let path: String
    let headers: [String: String]
    let body: Data?
}

/// Answers by request path, in order, and records every request.
private actor RoutedTransport: HTTPTransport {
    private var routes: [String: [ScriptedResponse]]
    private var seen: [SeenRequest] = []

    init(_ routes: [String: [ScriptedResponse]]) {
        self.routes = routes
    }

    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        // URLComponents keeps the trailing slash that URL.path drops.
        let path = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.path
        seen.append(SeenRequest(path: path, headers: request.allHTTPHeaderFields ?? [:], body: request.httpBody))
        guard var queue = routes[path], !queue.isEmpty else {
            XCTFail("Unexpected request to \(path)")
            throw URLError(.badServerResponse)
        }
        let next = queue.removeFirst()
        routes[path] = queue
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: next.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(next.body.utf8), response)
    }

    func requests() -> [SeenRequest] { seen }
}

private final class RecordingTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AuthTokens?
    private var saves: [AuthTokens] = []

    init(_ tokens: AuthTokens? = nil) { stored = tokens }

    func load() throws -> AuthTokens? { lock.withLock { stored } }
    func save(_ tokens: AuthTokens) throws {
        lock.withLock {
            stored = tokens
            saves.append(tokens)
        }
    }
    func clear() throws { lock.withLock { stored = nil } }
    func snapshot() -> AuthTokens? { lock.withLock { stored } }
    func savedPairs() -> [AuthTokens] { lock.withLock { saves } }
}

private func opaquePairJSON(access: String, refresh: String, withUser: Bool) -> String {
    let user = withUser
        ? #","user":{"id":"\#(userID)","email":"reader@example.org","display_name":"Reader"}"#
        : ""
    return #"{"access":"\#(access)","refresh":"\#(refresh)","token_type":"opaque","expires_in":1800,"refresh_expires_in":604800\#(user)}"#
}

private let refreshPath = "/api/v1/auth/token/refresh/"
private let mePath = "/api/v1/auth/me/"
private let profileJSON = #"{"id":"\#(userID)","email":"reader@example.org","display_name":"Reader"}"#
private let tokenNotValid = #"{"error":{"code":"AUTHENTICATION_FAILED","details":{"code":"token_not_valid"}}}"#

final class OpaqueTokenModelTests: XCTestCase {
    func testAcceptsOpaquePairAndLegacyJWTPair() throws {
        let opaque = try AuthTokens(access: "bat_" + opaqueBody, refresh: "brt_" + opaqueBody)
        XCTAssertEqual(opaque.format, .opaque)

        let legacy = try AuthTokens(access: legacyAccess, refresh: legacyRefresh)
        XCTAssertEqual(legacy.format, .legacyJWT)
    }

    func testRejectsMalformedSwappedAndMixedPairs() {
        let rejected: [(String, String)] = [
            (opaqueRefresh(), opaqueAccess()), // prefixes swapped
            (opaqueAccess(), legacyRefresh), // mixed formats
            (legacyAccess, opaqueRefresh()),
            ("bat_short", opaqueRefresh()), // body too short
            ("bat_" + String(repeating: "a", count: 42) + "=", opaqueRefresh()), // not base64url
            ("bat_" + String(repeating: "a", count: 40) + "a.b", opaqueRefresh()),
            ("BAT_" + String(repeating: "a", count: 43), opaqueRefresh()),
            ("", ""),
            ("not-a-token", "not-a-token"),
        ]
        for (access, refresh) in rejected {
            XCTAssertThrowsError(try AuthTokens(access: access, refresh: refresh), "\(access) / \(refresh)") {
                XCTAssertEqual($0 as? SessionError, .invalidToken)
            }
        }
    }

    func testSingleTokenChecksKeepKindsApart() {
        XCTAssertTrue(AuthTokens.isValidAccessToken(opaqueAccess()))
        XCTAssertTrue(AuthTokens.isValidAccessToken(legacyAccess))
        XCTAssertFalse(AuthTokens.isValidAccessToken(opaqueRefresh()))
        XCTAssertTrue(AuthTokens.isValidRefreshToken(opaqueRefresh()))
        XCTAssertTrue(AuthTokens.isValidRefreshToken(legacyRefresh))
        XCTAssertFalse(AuthTokens.isValidRefreshToken(opaqueAccess()))
    }

    func testLifetimesAreMeasuredFromTheResponseNotTheToken() throws {
        let received = Date(timeIntervalSince1970: 1_800_000_000)
        let tokens = try AuthTokens(
            access: opaqueAccess(),
            refresh: opaqueRefresh(),
            expiresIn: 1800,
            refreshExpiresIn: 604_800,
            receivedAt: received
        )
        XCTAssertEqual(tokens.accessExpiresAt, received.addingTimeInterval(1800))
        XCTAssertEqual(tokens.refreshExpiresAt, received.addingTimeInterval(604_800))
        XCTAssertFalse(tokens.isRefreshExpired(at: received.addingTimeInterval(604_799)))
        XCTAssertTrue(tokens.isRefreshExpired(at: received.addingTimeInterval(604_800)))
    }

    func testLegacyResponseHasNoLifetimeAndNeverCountsAsExpired() throws {
        let tokens = try AuthTokens(
            access: legacyAccess,
            refresh: legacyRefresh,
            expiresIn: nil,
            refreshExpiresIn: nil,
            receivedAt: Date()
        )
        XCTAssertNil(tokens.accessExpiresAt)
        XCTAssertNil(tokens.refreshExpiresAt)
        XCTAssertFalse(tokens.isRefreshExpired(at: .distantFuture))
    }

    func testKeychainRecordFromAnOlderBuildStillDecodes() throws {
        // What KeychainTokenStore wrote before opaque tokens: only the pair.
        let stored = Data(#"{"access":"\#(legacyAccess)","refresh":"\#(legacyRefresh)"}"#.utf8)
        let tokens = try JSONDecoder().decode(AuthTokens.self, from: stored)
        XCTAssertEqual(tokens, try AuthTokens(access: legacyAccess, refresh: legacyRefresh))
        XCTAssertNil(tokens.refreshExpiresAt)
    }

    func testOpaquePairRoundTripsThroughStorageEncodingWithLifetimes() throws {
        let tokens = try AuthTokens(
            access: opaqueAccess(),
            refresh: opaqueRefresh(),
            accessExpiresAt: Date(timeIntervalSince1970: 1_800_001_800),
            refreshExpiresAt: Date(timeIntervalSince1970: 1_800_604_800)
        )
        let decoded = try JSONDecoder().decode(AuthTokens.self, from: JSONEncoder().encode(tokens))
        XCTAssertEqual(decoded, tokens)
    }

    func testStoredRecordWithInvalidTokensIsRejected() {
        let stored = Data(#"{"access":"\#(opaqueAccess())","refresh":"\#(legacyRefresh)"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AuthTokens.self, from: stored))
    }
}

final class OpaqueTokenHeaderTests: XCTestCase {
    private let receivedAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testLoginOptsIntoOpaqueTokensAndTakesUserIDFromUser() async throws {
        let transport = RoutedTransport([
            "/api/v1/auth/login/": [.json(opaquePairJSON(access: opaqueAccess(), refresh: opaqueRefresh(), withUser: true))],
        ])
        let service = LiveAuthenticationService(baseURL: baseURL, transport: transport, now: { [receivedAt] in receivedAt })

        let session = try await service.login(email: "reader@example.org", password: "secret-password")

        let requests = await transport.requests()
        XCTAssertEqual(requests.first?.headers["X-Berynda-Token-Format"], "opaque")
        XCTAssertEqual(session.user.id, UUID(uuidString: userID))
        XCTAssertEqual(session.tokens.format, .opaque)
        XCTAssertEqual(session.tokens.accessExpiresAt, receivedAt.addingTimeInterval(1800))
        XCTAssertEqual(session.tokens.refreshExpiresAt, receivedAt.addingTimeInterval(604_800))
    }

    func testSocialLoginOptsIntoOpaqueTokens() async throws {
        let transport = RoutedTransport([
            "/api/v1/auth/social/login/": [.json(opaquePairJSON(access: opaqueAccess(), refresh: opaqueRefresh(), withUser: true))],
        ])
        let service = LiveAuthenticationService(baseURL: baseURL, transport: transport)

        let session = try await service.socialLogin(
            SocialCredential(provider: .apple, challengeID: UUID(), identityToken: "provider.identity.signature")
        )

        let requests = await transport.requests()
        XCTAssertEqual(requests.first?.headers["X-Berynda-Token-Format"], "opaque")
        XCTAssertEqual(session.tokens.format, .opaque)
    }

    func testRefreshOptsIntoOpaqueTokensForBothFormats() async throws {
        let transport = RoutedTransport([
            refreshPath: [
                .json(opaquePairJSON(access: opaqueAccess("b"), refresh: opaqueRefresh("s"), withUser: false)),
                .json(opaquePairJSON(access: opaqueAccess("c"), refresh: opaqueRefresh("t"), withUser: false)),
            ],
        ])
        let service = LiveAuthenticationService(baseURL: baseURL, transport: transport)

        let upgraded = try await service.refresh(refreshToken: legacyRefresh)
        let rotated = try await service.refresh(refreshToken: upgraded.refresh)

        let requests = await transport.requests()
        XCTAssertEqual(requests.map { $0.headers["X-Berynda-Token-Format"] }, ["opaque", "opaque"])
        XCTAssertEqual(upgraded.refresh, opaqueRefresh("s"))
        XCTAssertEqual(rotated.refresh, opaqueRefresh("t"))
    }

    func testPasswordChangeOptsIntoOpaqueTokensAndReturnsTheRotatedPair() async throws {
        let transport = RoutedTransport([
            "/api/v1/auth/me/password/": [.json(opaquePairJSON(access: opaqueAccess("p"), refresh: opaqueRefresh("p"), withUser: false))],
        ])
        let service = LiveAuthenticationService(baseURL: baseURL, transport: transport, now: { [receivedAt] in receivedAt })

        let tokens = try await service.changePassword(
            currentPassword: "old-secret",
            newPassword: "new-secret-1",
            accessToken: opaqueAccess()
        )

        let requests = await transport.requests()
        XCTAssertEqual(requests.first?.headers["X-Berynda-Token-Format"], "opaque")
        XCTAssertEqual(requests.first?.headers["Authorization"], "Bearer \(opaqueAccess())")
        XCTAssertEqual(tokens.access, opaqueAccess("p"))
        XCTAssertEqual(tokens.refresh, opaqueRefresh("p"))
        XCTAssertEqual(tokens.refreshExpiresAt, receivedAt.addingTimeInterval(604_800))
    }

    func testEndpointsThatIssueNoTokensDoNotSendTheHeader() async throws {
        let transport = RoutedTransport([
            "/api/v1/auth/password-reset/": [.json(#"{"status":"ok"}"#)],
            "/api/v1/auth/logout/": [ScriptedResponse(status: 204, body: "")],
        ])
        let service = LiveAuthenticationService(baseURL: baseURL, transport: transport)

        try await service.requestPasswordReset(email: "reader@example.org")
        try await service.logout(accessToken: opaqueAccess(), refreshToken: opaqueRefresh())

        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.headers["X-Berynda-Token-Format"] == nil })
        XCTAssertEqual(requests[1].headers["Authorization"], "Bearer \(opaqueAccess())")
    }

    func testOpaqueRefreshReturningAMixedPairIsRejected() async {
        let transport = RoutedTransport([
            refreshPath: [.json(opaquePairJSON(access: opaqueAccess(), refresh: legacyRefresh, withUser: false))],
        ])
        let service = LiveAuthenticationService(baseURL: baseURL, transport: transport)
        do {
            _ = try await service.refresh(refreshToken: opaqueRefresh())
            XCTFail("A mixed pair must not be accepted")
        } catch {
            XCTAssertEqual(error as? SessionError, .invalidToken)
        }
    }
}

final class OpaqueTokenUpgradeTests: XCTestCase {
    /// A reader signed in on an older build has a JWT pair in the Keychain.
    /// Their first 401 refreshes with the JWT; the server exchanges it for an
    /// opaque pair, which is stored as one value, and the request is retried.
    func testStoredLegacyJWTIsExchangedOnFirstRefreshAndReaderStaysSignedIn() async throws {
        let store = RecordingTokenStore(try AuthTokens(access: legacyAccess, refresh: legacyRefresh))
        let transport = RoutedTransport([
            mePath: [.json(tokenNotValid, status: 401), .json(profileJSON)],
            refreshPath: [.json(opaquePairJSON(access: opaqueAccess(), refresh: opaqueRefresh(), withUser: false))],
        ])
        let session = SessionController(
            tokenStore: store,
            authentication: LiveAuthenticationService(baseURL: baseURL, transport: transport)
        )
        let client = BeryndaAPIClient(baseURL: baseURL, transport: transport, authorizationSession: session)

        try await client.send(.accountProfile, method: .get)

        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.path), [mePath, refreshPath, mePath])
        XCTAssertEqual(requests[0].headers["Authorization"], "Bearer \(legacyAccess)")
        XCTAssertEqual(requests[1].headers["X-Berynda-Token-Format"], "opaque")
        let refreshBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests[1].body)) as? [String: Any])
        XCTAssertEqual(refreshBody["refresh"] as? String, legacyRefresh)
        XCTAssertEqual(requests[2].headers["Authorization"], "Bearer \(opaqueAccess())")

        XCTAssertEqual(store.savedPairs().count, 1)
        let stored = try XCTUnwrap(store.snapshot())
        XCTAssertEqual(stored.access, opaqueAccess())
        XCTAssertEqual(stored.refresh, opaqueRefresh())
        XCTAssertNotNil(stored.refreshExpiresAt)
        let state = await session.state()
        XCTAssertEqual(state, .authenticated)
    }

    /// A rotated-away refresh token revokes the sign-in. A 401 from refresh
    /// therefore ends the session; the old token is never sent again.
    func testRefresh401EndsTheSessionWithoutRetryingAnOlderToken() async throws {
        let store = RecordingTokenStore(try AuthTokens(access: opaqueAccess(), refresh: opaqueRefresh()))
        let transport = RoutedTransport([
            mePath: [.json(tokenNotValid, status: 401)],
            refreshPath: [.json(tokenNotValid, status: 401)],
        ])
        let session = SessionController(
            tokenStore: store,
            authentication: LiveAuthenticationService(baseURL: baseURL, transport: transport)
        )
        let client = BeryndaAPIClient(baseURL: baseURL, transport: transport, authorizationSession: session)

        do {
            try await client.send(.accountProfile, method: .get)
            XCTFail("Expected the request to fail unauthorized")
        } catch {
            guard case .unauthorized = error as? APIError else {
                return XCTFail("Expected APIError.unauthorized, got \(error)")
            }
        }

        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.path), [mePath, refreshPath])
        XCTAssertNil(store.snapshot())
        let state = await session.state()
        XCTAssertEqual(state, .expired)
        let access = await session.accessToken()
        XCTAssertNil(access)
    }

    func testPastRefreshLifetimeAsksForSignInWithoutANetworkCall() async throws {
        let issued = Date(timeIntervalSince1970: 1_800_000_000)
        let store = RecordingTokenStore(try AuthTokens(
            access: opaqueAccess(),
            refresh: opaqueRefresh(),
            expiresIn: 1800,
            refreshExpiresIn: 604_800,
            receivedAt: issued
        ))
        let transport = RoutedTransport([:])
        let later = issued.addingTimeInterval(604_801)
        let session = SessionController(
            tokenStore: store,
            authentication: LiveAuthenticationService(baseURL: baseURL, transport: transport),
            now: { later }
        )

        let state = await session.state()
        XCTAssertEqual(state, .expired)
        do {
            _ = try await session.refreshAccessToken(rejectedAccessToken: opaqueAccess())
            XCTFail("Expected expiry")
        } catch {
            XCTAssertEqual(error as? SessionError, .expired)
        }
        let requests = await transport.requests()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNil(store.snapshot())
    }

    /// A rotation that completes after sign-out must not bring the session back.
    func testRotationLandingAfterSignOutIsNotStored() async throws {
        let store = RecordingTokenStore(try AuthTokens(access: opaqueAccess(), refresh: opaqueRefresh()))
        let gate = SlowRefresh(rotated: try AuthTokens(access: opaqueAccess("n"), refresh: opaqueRefresh("n")))
        let session = SessionController(tokenStore: store, authentication: gate)

        let refresh = Task { try await session.refreshAccessToken(rejectedAccessToken: opaqueAccess()) }
        await gate.waitUntilRefreshing()
        try await session.signOut()
        await gate.finish()

        do {
            _ = try await refresh.value
            XCTFail("A refresh that outlived the session must not succeed")
        } catch {}
        XCTAssertNil(store.snapshot())
        XCTAssertTrue(store.savedPairs().isEmpty)
        let state = await session.state()
        XCTAssertEqual(state, .anonymous)
    }
}

/// An authentication service whose refresh waits for the test to let it go,
/// ignoring cancellation the way a request already on the wire would.
private actor SlowRefresh: AuthenticationServing {
    private let rotated: AuthTokens
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(rotated: AuthTokens) { self.rotated = rotated }

    func refresh(refreshToken: String) async throws -> AuthTokens {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters = []
        if !released {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        return rotated
    }

    func waitUntilRefreshing() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters = []
    }

    func login(email: String, password: String) async throws -> AuthSession { throw SessionError.unavailable }
    func register(email: String, password: String, displayName: String) async throws -> RegistrationResult {
        throw SessionError.unavailable
    }
    func confirmEmail(token: String) async throws -> UserProfile { throw SessionError.unavailable }
    func requestPasswordReset(email: String) async throws {}
    func confirmPasswordReset(uid: String, token: String, newPassword: String) async throws {}
    func logout(accessToken: String, refreshToken: String) async throws {}
}
