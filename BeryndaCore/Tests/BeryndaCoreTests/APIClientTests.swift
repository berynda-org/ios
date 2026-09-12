import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import BeryndaCore

private struct StubTransport: HTTPTransport {
    let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    func data(
        for request: URLRequest,
        maximumBytes: Int
    ) async throws -> (Data, HTTPURLResponse) {
        try handler(request)
    }
}

private struct StubResponse: Sendable {
    let status: Int
    let data: Data
    let headers: [String: String]

    init(status: Int, data: Data = Data(), headers: [String: String] = [:]) {
        self.status = status
        self.data = data
        self.headers = headers
    }
}

private actor SequenceTransport: HTTPTransport {
    private var responses: [StubResponse]
    private var requestIDs: [String?] = []
    private var responseLimits: [Int] = []
    private var authorizationHeaders: [String?] = []

    init(_ responses: [StubResponse]) {
        self.responses = responses
    }

    func data(
        for request: URLRequest,
        maximumBytes: Int
    ) async throws -> (Data, HTTPURLResponse) {
        requestIDs.append(request.value(forHTTPHeaderField: "X-Request-ID"))
        responseLimits.append(maximumBytes)
        authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization"))
        let item = responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: item.status,
            httpVersion: nil,
            headerFields: item.headers
        )!
        return (item.data, response)
    }

    func callCount() -> Int { requestIDs.count }
    func observedRequestIDs() -> [String?] { requestIDs }
    func observedResponseLimits() -> [Int] { responseLimits }
    func observedAuthorizationHeaders() -> [String?] { authorizationHeaders }
}

private actor DelayRecorder {
    private var values: [TimeInterval] = []

    func sleep(_ seconds: TimeInterval) {
        values.append(seconds)
    }

    func recorded() -> [TimeInterval] { values }
}

private actor AuthorizationStub: AuthorizationSession {
    private let original: String?
    private let refreshed: String
    private let refreshError: SessionError?
    private var refreshCallsValue = 0

    init(original: String?, refreshed: String, refreshError: SessionError? = nil) {
        self.original = original
        self.refreshed = refreshed
        self.refreshError = refreshError
    }

    func accessToken() -> String? { original }

    func refreshAccessToken(rejectedAccessToken: String) async throws -> String {
        refreshCallsValue += 1
        if let refreshError { throw refreshError }
        return refreshed
    }

    func refreshCalls() -> Int { refreshCallsValue }
}

final class APIClientTests: XCTestCase {
    func testAddsLanguageAndRequestIDWithoutCredentials() async throws {
        let data = try fixture("works-page")
        let transport = StubTransport { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Language"), "uk")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Request-ID"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (data, Self.response(url: request.url!, status: 200))
        }
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        let page: PaginatedResponse<WorkSummary> = try await client.request(
            .works(search: "Енеїда", page: 1)
        )
        XCTAssertEqual(page.results.count, 1)
    }

    func testMapsForbiddenWithoutDecodingBody() async {
        let transport = StubTransport { request in
            (Data("secret detail".utf8), Self.response(url: request.url!, status: 403))
        }
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        do {
            let _: PaginatedResponse<WorkSummary> = try await client.request(.works(search: nil, page: 1))
            XCTFail("Expected forbidden")
        } catch {
            XCTAssertEqual(
                error as? APIError,
                .forbidden(APIErrorContext())
            )
        }
    }

    func testBinaryRequestsPassTheAPIsJSONContentNegotiation() async throws {
        // Reproduce the live API's 406 response when its JSON renderer cannot
        // negotiate, even though the endpoint ultimately serves a binary file.
        for mimeType in ["image/jpeg", "application/pdf", "application/epub+zip"] {
            let expected = Data("binary fixture".utf8)
            let transport = StubTransport { request in
                let acceptsJSON = request.value(forHTTPHeaderField: "Accept")?
                    .contains("application/json") == true
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: acceptsJSON ? 200 : 406,
                    httpVersion: nil,
                    headerFields: ["Content-Type": acceptsJSON ? mimeType : "application/json"]
                )!
                return (acceptsJSON ? expected : Data("{}".utf8), response)
            }
            let client = BeryndaAPIClient(
                baseURL: URL(string: "https://berynda.org/api/v1/")!,
                transport: transport
            )
            let payload = try await client.data(
                .readerContent(fileID: UUID(), structuredText: false),
                accept: mimeType == "image/jpeg" ? "image/*" : mimeType
            )
            XCTAssertEqual(payload.contentType, mimeType)
            XCTAssertEqual(payload.data, expected)
        }
    }

    func testBinaryPayloadNormalizesContentType() async throws {
        let transport = StubTransport { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "Application/PDF; charset=binary"]
            )!
            return (Data("%PDF".utf8), response)
        }
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        let payload = try await client.data(.readerContent(fileID: UUID(), structuredText: false))
        XCTAssertEqual(payload.contentType, "application/pdf")
    }

    func testTypedJSONRejectsSuccessfulHTMLResponse() async {
        let transport = StubTransport { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/html"]
            )!
            return (Data("<html></html>".utf8), response)
        }
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        do {
            let _: PaginatedResponse<WorkSummary> = try await client.request(
                .works(search: nil, page: 1)
            )
            XCTFail("Expected content-type validation failure")
        } catch {
            XCTAssertEqual(error as? APIError, .unsupportedContentType("text/html"))
        }
    }

    func testTypedJSONRejectsOversizedDeclaredResponse() async {
        let transport = StubTransport { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json",
                    "Content-Length": "6000000",
                ]
            )!
            return (Data("{}".utf8), response)
        }
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        do {
            let _: PaginatedResponse<WorkSummary> = try await client.request(
                .works(search: nil, page: 1)
            )
            XCTFail("Expected size validation failure")
        } catch {
            XCTAssertEqual(error as? APIError, .responseTooLarge)
        }
    }

    func testClientRejectsOversizedReceivedResponseFromCustomTransport() async {
        let transport = StubTransport { request in
            let response = Self.response(url: request.url!, status: 200)
            return (Data(repeating: 0x61, count: 5), response)
        }
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport
        )

        do {
            _ = try await client.data(
                .readerContent(fileID: UUID(), structuredText: false),
                maximumBytes: 4
            )
            XCTFail("Expected size validation failure")
        } catch {
            XCTAssertEqual(error as? APIError, .responseTooLarge)
        }
    }

    func testRetriesTransientServerFailureThenSucceeds() async throws {
        let fixtureData = try fixture("works-page")
        let transport = SequenceTransport([
            StubResponse(status: 503),
            StubResponse(
                status: 200,
                data: fixtureData,
                headers: ["Content-Type": "application/json"]
            ),
        ])
        let delays = DelayRecorder()
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport,
            retryPolicy: RetryPolicy(maximumAttempts: 3, baseDelay: 0.25),
            sleeper: { seconds in await delays.sleep(seconds) },
            jitter: { 1 }
        )

        let page: PaginatedResponse<WorkSummary> = try await client.request(
            .works(search: nil, page: 1)
        )

        XCTAssertEqual(page.results.count, 1)
        let callCount = await transport.callCount()
        let recordedDelays = await delays.recorded()
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(recordedDelays, [0.25])
        let observedRequestIDs = await transport.observedRequestIDs()
        let requestIDs = observedRequestIDs.compactMap { $0 }
        let responseLimits = await transport.observedResponseLimits()
        XCTAssertEqual(Set(requestIDs).count, 1)
        XCTAssertEqual(responseLimits, [5 * 1_024 * 1_024, 5 * 1_024 * 1_024])
    }

    func testRetryAfterIsCapped() async throws {
        let fixtureData = try fixture("works-page")
        let transport = SequenceTransport([
            StubResponse(status: 429, headers: ["Retry-After": "120"]),
            StubResponse(
                status: 200,
                data: fixtureData,
                headers: ["Content-Type": "application/json"]
            ),
        ])
        let delays = DelayRecorder()
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport,
            retryPolicy: RetryPolicy(maximumRetryAfter: 0.5),
            sleeper: { seconds in await delays.sleep(seconds) },
            jitter: { 1 }
        )

        let _: PaginatedResponse<WorkSummary> = try await client.request(
            .works(search: nil, page: 1)
        )

        let recordedDelays = await delays.recorded()
        XCTAssertEqual(recordedDelays, [0.5])
    }

    func testCancellationDuringBackoffStopsRetrying() async {
        let transport = SequenceTransport([
            StubResponse(status: 503),
            StubResponse(status: 200),
        ])
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport,
            sleeper: { _ in throw CancellationError() },
            jitter: { 1 }
        )

        do {
            let _: PaginatedResponse<WorkSummary> = try await client.request(
                .works(search: nil, page: 1)
            )
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            let callCount = await transport.callCount()
            XCTAssertEqual(callCount, 1)
        } catch {
            XCTFail("Expected CancellationError, received \(error)")
        }
    }

    func testNonTransientForbiddenResponseIsNotRetriedAndCarriesSafeContext() async {
        let data = Data(
            #"{"code":"permission_\u0000denied","detail":"private detail","request_id":"body-id"}"#.utf8
        )
        let transport = SequenceTransport([
            StubResponse(
                status: 403,
                data: data,
                headers: ["X-Request-ID": "header-id"]
            ),
        ])
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport,
            sleeper: { _ in XCTFail("Forbidden response must not retry") }
        )

        do {
            let _: PaginatedResponse<WorkSummary> = try await client.request(
                .works(search: nil, page: 1)
            )
            XCTFail("Expected forbidden")
        } catch {
            XCTAssertEqual(
                error as? APIError,
                .forbidden(
                    APIErrorContext(code: "permission_denied", requestID: "header-id")
                )
            )
            let callCount = await transport.callCount()
            XCTAssertEqual(callCount, 1)
        }
    }

    func testExhaustedServerRetriesReturnLastStructuredError() async {
        let errorBody = Data(#"{"code":"temporarily_unavailable"}"#.utf8)
        let transport = SequenceTransport([
            StubResponse(status: 503),
            StubResponse(status: 503),
            StubResponse(
                status: 503,
                data: errorBody,
                headers: ["X-Request-ID": "final-request"]
            ),
        ])
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport,
            retryPolicy: RetryPolicy(maximumAttempts: 3, baseDelay: 0),
            sleeper: { _ in },
            jitter: { 1 }
        )

        do {
            let _: PaginatedResponse<WorkSummary> = try await client.request(
                .works(search: nil, page: 1)
            )
            XCTFail("Expected server error")
        } catch {
            XCTAssertEqual(
                error as? APIError,
                .server(
                    status: 503,
                    context: APIErrorContext(
                        code: "temporarily_unavailable",
                        requestID: "final-request"
                    )
                )
            )
            let callCount = await transport.callCount()
            XCTAssertEqual(callCount, 3)
        }
    }

    func testAuthenticatedRequestRefreshesOnceAndReplaysWithRotatedAccessToken() async throws {
        let fixtureData = try fixture("works-page")
        let oldAccess = "header.old-access.signature"
        let newAccess = "header.new-access.signature"
        let session = AuthorizationStub(original: oldAccess, refreshed: newAccess)
        let transport = SequenceTransport([
            StubResponse(status: 401),
            StubResponse(
                status: 200,
                data: fixtureData,
                headers: ["Content-Type": "application/json"]
            ),
        ])
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport,
            authorizationSession: session
        )

        let page: PaginatedResponse<WorkSummary> = try await client.request(
            .works(search: nil, page: 1)
        )

        let headers = await transport.observedAuthorizationHeaders()
        let refreshCalls = await session.refreshCalls()
        XCTAssertEqual(page.results.count, 1)
        XCTAssertEqual(headers.compactMap { $0 }, ["Bearer \(oldAccess)", "Bearer \(newAccess)"])
        XCTAssertEqual(refreshCalls, 1)
    }

    func testFailedSessionRefreshDoesNotReplayUnauthorizedRequest() async {
        let oldAccess = "header.old-access.signature"
        let session = AuthorizationStub(
            original: oldAccess,
            refreshed: "header.unused.signature",
            refreshError: .expired
        )
        let transport = SequenceTransport([StubResponse(status: 401)])
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport,
            authorizationSession: session
        )

        do {
            let _: PaginatedResponse<WorkSummary> = try await client.request(
                .works(search: nil, page: 1)
            )
            XCTFail("Expected unauthorized")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized(APIErrorContext()))
        }

        let callCount = await transport.callCount()
        let refreshCalls = await session.refreshCalls()
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(refreshCalls, 1)
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private static func response(url: URL, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}
