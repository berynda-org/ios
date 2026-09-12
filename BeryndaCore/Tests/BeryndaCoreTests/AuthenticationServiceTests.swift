import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import BeryndaCore

private struct AuthStubResponse: Sendable {
    let status: Int
    let data: Data
    let headers: [String: String]

    init(status: Int, data: Data = Data(), headers: [String: String] = [:]) {
        self.status = status
        self.data = data
        self.headers = headers
    }
}

private struct RecordedAuthRequest: Sendable {
    let url: URL?
    let method: String?
    let headers: [String: String]
    let body: Data?
    let maximumBytes: Int
}

private actor AuthTransportStub: HTTPTransport {
    private var responses: [AuthStubResponse]
    private var requests: [RecordedAuthRequest] = []

    init(_ responses: [AuthStubResponse]) {
        self.responses = responses
    }

    func data(
        for request: URLRequest,
        maximumBytes: Int
    ) async throws -> (Data, HTTPURLResponse) {
        requests.append(
            RecordedAuthRequest(
                url: request.url,
                method: request.httpMethod,
                headers: request.allHTTPHeaderFields ?? [:],
                body: request.httpBody,
                maximumBytes: maximumBytes
            )
        )
        let next = responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: next.status,
            httpVersion: nil,
            headerFields: next.headers
        )!
        return (next.data, response)
    }

    func recordedRequests() -> [RecordedAuthRequest] { requests }
}

final class AuthenticationServiceTests: XCTestCase {
    func testLoginRefreshAndLogoutMatchMobileBodyContract() async throws {
        let access1 = "header.access-one.signature"
        let refresh1 = "header.refresh-one.signature"
        let access2 = "header.access-two.signature"
        let refresh2 = "header.refresh-two.signature"
        let loginData = Data(
            """
            {"access":"\(access1)","refresh":"\(refresh1)","user":{"id":"11111111-1111-1111-1111-111111111111","email":"reader@example.org","display_name":"Reader"}}
            """.utf8
        )
        let refreshData = Data(
            "{\"access\":\"\(access2)\",\"refresh\":\"\(refresh2)\"}".utf8
        )
        let transport = AuthTransportStub([
            AuthStubResponse(
                status: 200,
                data: loginData,
                headers: ["Content-Type": "application/json"]
            ),
            AuthStubResponse(
                status: 200,
                data: refreshData,
                headers: ["Content-Type": "application/json"]
            ),
            AuthStubResponse(status: 204),
        ])
        let service = LiveAuthenticationService(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        let session = try await service.login(
            email: "  reader@example.org  ",
            password: "correct horse battery staple"
        )
        let rotated = try await service.refresh(refreshToken: session.tokens.refresh)
        try await service.logout(
            accessToken: rotated.access,
            refreshToken: rotated.refresh
        )

        XCTAssertEqual(session.tokens, try AuthTokens(access: access1, refresh: refresh1))
        XCTAssertEqual(session.user.email, "reader@example.org")
        XCTAssertEqual(rotated, try AuthTokens(access: access2, refresh: refresh2))

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://berynda.org/api/v1/auth/login/",
            "https://berynda.org/api/v1/auth/token/refresh/",
            "https://berynda.org/api/v1/auth/logout/",
        ])
        XCTAssertEqual(requests.map(\.method), ["POST", "POST", "POST"])
        XCTAssertTrue(requests.allSatisfy { $0.maximumBytes == 1 * 1_024 * 1_024 })
        XCTAssertTrue(requests.allSatisfy { $0.headers["Content-Type"] == "application/json" })
        XCTAssertNil(requests[0].headers["Authorization"])
        XCTAssertNil(requests[1].headers["Authorization"])
        XCTAssertEqual(requests[2].headers["Authorization"], "Bearer \(access2)")

        let loginBody = try jsonObject(requests[0].body)
        let refreshBody = try jsonObject(requests[1].body)
        let logoutBody = try jsonObject(requests[2].body)
        XCTAssertEqual(loginBody["email"] as? String, "reader@example.org")
        XCTAssertEqual(loginBody["password"] as? String, "correct horse battery staple")
        XCTAssertEqual(refreshBody["refresh"] as? String, refresh1)
        XCTAssertEqual(logoutBody["refresh"] as? String, refresh2)
    }

    func testLogin401IsInvalidCredentialsWithoutReturningServerDetail() async {
        let privateBody = Data(
            #"{"error":{"code":"CREDENTIALS_INVALID","message":"private server detail"}}"#.utf8
        )
        let transport = AuthTransportStub([
            AuthStubResponse(
                status: 401,
                data: privateBody,
                headers: ["Content-Type": "application/json"]
            ),
        ])
        let service = LiveAuthenticationService(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        do {
            _ = try await service.login(email: "reader@example.org", password: "wrong")
            XCTFail("Expected invalid credentials")
        } catch {
            XCTAssertEqual(error as? SessionError, .invalidCredentials)
            XCTAssertFalse(error.localizedDescription.contains("private server detail"))
        }
    }

    func testRefresh401ExpiresSession() async {
        let transport = AuthTransportStub([AuthStubResponse(status: 401)])
        let service = LiveAuthenticationService(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        do {
            _ = try await service.refresh(refreshToken: "header.refresh.signature")
            XCTFail("Expected expiry")
        } catch {
            XCTAssertEqual(error as? SessionError, .expired)
        }
    }

    func testSuccessfulHTMLLoginIsRejected() async {
        let transport = AuthTransportStub([
            AuthStubResponse(
                status: 200,
                data: Data("<html></html>".utf8),
                headers: ["Content-Type": "text/html"]
            ),
        ])
        let service = LiveAuthenticationService(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        do {
            _ = try await service.login(email: "reader@example.org", password: "secret")
            XCTFail("Expected invalid response")
        } catch {
            XCTAssertEqual(error as? SessionError, .invalidResponse)
        }
    }

    func testRegistrationAndPasswordResetUseNativeJSONContracts() async throws {
        let registration = Data(
            #"{"id":"11111111-1111-1111-1111-111111111111","email":"reader@example.org","activation":"email_confirmation_required"}"#.utf8
        )
        let transport = AuthTransportStub([
            AuthStubResponse(status: 201, data: registration, headers: ["Content-Type": "application/json"]),
            AuthStubResponse(status: 200, data: Data(#"{"status":"ok"}"#.utf8), headers: ["Content-Type": "application/json"]),
        ])
        let service = LiveAuthenticationService(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        let result = try await service.register(
            email: " reader@example.org ",
            password: "password123",
            displayName: " Читач "
        )
        try await service.requestPasswordReset(email: " reader@example.org ")

        XCTAssertTrue(result.requiresEmailConfirmation)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://berynda.org/api/v1/auth/register/",
            "https://berynda.org/api/v1/auth/password-reset/",
        ])
        let registrationBody = try jsonObject(requests[0].body)
        XCTAssertEqual(registrationBody["email"] as? String, "reader@example.org")
        XCTAssertEqual(registrationBody["display_name"] as? String, "Читач")
        XCTAssertEqual(registrationBody["password"] as? String, "password123")
        let resetBody = try jsonObject(requests[1].body)
        XCTAssertEqual(resetBody["email"] as? String, "reader@example.org")
    }

    func testEmailAndPasswordConfirmationUseNativeContracts() async throws {
        let profile = Data(
            #"{"id":"11111111-1111-1111-1111-111111111111","email":"reader@example.org","display_name":"Читач"}"#.utf8
        )
        let transport = AuthTransportStub([
            AuthStubResponse(status: 200, data: profile, headers: ["Content-Type": "application/json"]),
            AuthStubResponse(
                status: 200,
                data: Data(#"{"status":"password_updated"}"#.utf8),
                headers: ["Content-Type": "application/json"]
            ),
        ])
        let service = LiveAuthenticationService(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        let confirmed = try await service.confirmEmail(token: "signed:confirmation-token")
        try await service.confirmPasswordReset(
            uid: "encoded-user",
            token: "reset-token",
            newPassword: "new-password-123"
        )

        XCTAssertEqual(confirmed.email, "reader@example.org")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://berynda.org/api/v1/auth/confirm-email/signed:confirmation-token/",
            "https://berynda.org/api/v1/auth/password-reset/confirm/",
        ])
        XCTAssertEqual(requests.map(\.method), ["GET", "POST"])
        XCTAssertNil(requests[0].body)
        let resetBody = try jsonObject(requests[1].body)
        XCTAssertEqual(resetBody["uid"] as? String, "encoded-user")
        XCTAssertEqual(resetBody["token"] as? String, "reset-token")
        XCTAssertEqual(resetBody["new_password"] as? String, "new-password-123")
        XCTAssertEqual(resetBody["new_password_confirm"] as? String, "new-password-123")
    }

    func testConfirmationRejectsPathInjectionBeforeNetwork() async {
        let transport = AuthTransportStub([])
        let service = LiveAuthenticationService(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        do {
            _ = try await service.confirmEmail(token: "unsafe/../token")
            XCTFail("Expected invalid input")
        } catch {
            XCTAssertEqual(error as? SessionError, .invalidInput)
        }
        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }


    func testSocialChallengeAndLoginUseNonceAndStoreBeryndaTokens() async throws {
        let challengeID = UUID()
        let challengeJSON = "{\"challenge_id\":\"\(challengeID)\",\"nonce\":\"one-time-challenge\",\"expires_in\":300}"
        let login = #"{"access":"header.access.signature","refresh":"header.refresh.signature","user":{"id":"11111111-1111-1111-1111-111111111111","email":"reader@example.org"}}"#
        let transport = AuthTransportStub([
            AuthStubResponse(status: 200, data: Data(challengeJSON.utf8), headers: ["Content-Type": "application/json"]),
            AuthStubResponse(status: 200, data: Data(login.utf8), headers: ["Content-Type": "application/json"]),
        ])
        let service = LiveAuthenticationService(baseURL: URL(string: "https://berynda.org/api/v1/")!, transport: transport)
        let challenge = try await service.socialChallenge(provider: .apple, accessToken: nil)
        XCTAssertEqual(challenge.nonce, "one-time-challenge")
        let credential = SocialCredential(provider: .apple, challengeID: challenge.challengeID, identityToken: "provider.identity.signature")
        let session = try await service.socialLogin(credential)
        XCTAssertEqual(session.tokens.access, "header.access.signature")
        XCTAssertFalse(credential.description.contains(credential.identityToken))
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests[0].url?.path, "/api/v1/auth/social/challenge/")
        XCTAssertEqual(try jsonObject(requests[0].body)["link_account"] as? Bool, false)
        XCTAssertEqual(try jsonObject(requests[1].body)["identity_token"] as? String, "provider.identity.signature")
        XCTAssertNil(requests[1].headers["Authorization"])
    }

    func testSocialEmailCollisionOffersExplicitLinking() async {
        let transport = AuthTransportStub([
            AuthStubResponse(status: 409, data: Data(#"{"error":{"code":"SOCIAL_ACCOUNT_EXISTS"}}"#.utf8), headers: ["Content-Type": "application/json"]),
        ])
        let service = LiveAuthenticationService(baseURL: URL(string: "https://berynda.org/api/v1/")!, transport: transport)
        do {
            _ = try await service.socialLogin(SocialCredential(provider: .google, challengeID: UUID(), identityToken: "token"))
            XCTFail("Must not silently merge existing accounts")
        } catch { XCTAssertEqual(error as? SessionError, .socialAccountExists) }
    }

    private func jsonObject(_ data: Data?) throws -> [String: Any] {
        let data = try XCTUnwrap(data)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
