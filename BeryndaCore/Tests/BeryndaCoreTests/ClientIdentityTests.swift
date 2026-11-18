import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import BeryndaCore

private actor CapturingTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []

    func data(
        for request: URLRequest,
        maximumBytes: Int
    ) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data("{}".utf8), response)
    }
}

final class ClientIdentityTests: XCTestCase {
    private let identity = ClientIdentity(version: "0.1.0", build: "42", systemVersion: "18.2.0")

    func testHeaderAndUserAgentFormat() {
        XCTAssertEqual(identity.headerValue, "ios/0.1.0")
        XCTAssertEqual(identity.userAgent, "Berynda-iOS/0.1.0 (42; iOS 18.2.0)")
    }

    /// The server accepts `ios/[0-9A-Za-z.+-]{1,32}` and silently ignores
    /// anything else, so a bad version must be cleaned, never sent raw.
    func testVersionIsCleanedToTheServersPattern() {
        let pattern = try! NSRegularExpression(pattern: "^ios/[0-9A-Za-z.+-]{1,32}$")
        for version in ["1.0 beta (3)", "1.0;drop", String(repeating: "9", count: 40), "", "ї"] {
            let value = ClientIdentity(version: version, build: nil, systemVersion: "18.0.0").headerValue
            let range = NSRange(value.startIndex..., in: value)
            XCTAssertNotNil(pattern.firstMatch(in: value, range: range), "\(version) → \(value)")
        }
        XCTAssertEqual(ClientIdentity(version: "", build: nil, systemVersion: "").headerValue, "ios/unknown")
        XCTAssertEqual(ClientIdentity(version: "", build: nil, systemVersion: "").userAgent, "Berynda-iOS/unknown")
    }

    func testAPIClientSendsIdentity() async throws {
        let transport = CapturingTransport()
        let client = BeryndaAPIClient(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport,
            clientIdentity: identity
        )
        _ = try? await client.data(.readerContent(fileID: UUID(), structuredText: false))

        let first = await transport.requests.first
        let request = try XCTUnwrap(first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Berynda-Client"), "ios/0.1.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), identity.userAgent)
    }

    func testAuthenticationServiceSendsIdentity() async throws {
        let transport = CapturingTransport()
        let service = LiveAuthenticationService(
            baseURL: URL(string: "https://berynda.org/api/v1/")!,
            transport: transport,
            clientIdentity: identity
        )
        _ = try? await service.socialConfiguration()

        let first = await transport.requests.first
        let request = try XCTUnwrap(first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Berynda-Client"), "ios/0.1.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), identity.userAgent)
    }
}
