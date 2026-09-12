import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import BeryndaCore

private struct ReaderStubTransport: HTTPTransport {
    let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    func data(
        for request: URLRequest,
        maximumBytes: Int
    ) async throws -> (Data, HTTPURLResponse) {
        try handler(request)
    }
}

final class ReaderRepositoryTests: XCTestCase {
    func testReaderInfoDecodesWithoutUsingWebModeFiles() async throws {
        let data = try fixture("reader-info-text")
        let repository = repository { request in
            return (data, Self.response(request, contentType: "application/json"))
        }

        let info = try await repository.info(
            fileID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        )

        XCTAssertEqual(info.renderingMode, .text)
        XCTAssertEqual(info.pageDelivery, .clientFull)
        XCTAssertTrue(info.rights.canCopyText)
        XCTAssertEqual(info.toc.first?.title, "Частина перша")
    }

    func testStructuredTextUsesJSONDeliveryAndDecodesBody() async throws {
        let repository = repository { request in
            XCTAssertEqual(
                URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "delivery" })?.value,
                "json"
            )
            let data = Data(#"{"body":"Рядок","page_offsets":[]}"#.utf8)
            return (data, Self.response(request, contentType: "application/json; charset=utf-8"))
        }

        let content = try await repository.text(fileID: UUID())
        XCTAssertEqual(content.body, "Рядок")
    }

    func testPDFRejectsHTMLEvenWithSuccessfulStatus() async {
        let repository = repository { request in
            (Data("<html>login</html>".utf8), Self.response(request, contentType: "text/html"))
        }

        do {
            _ = try await repository.fullDocument(fileID: UUID())
            XCTFail("Expected MIME validation failure")
        } catch {
            XCTAssertEqual(error as? APIError, .unsupportedContentType("text/html"))
        }
    }

    func testPagePDFRequiresPDFSignature() async {
        let repository = repository { request in
            (Data("not a pdf".utf8), Self.response(request, contentType: "application/pdf"))
        }

        do {
            _ = try await repository.pagePDF(fileID: UUID(), page: 1)
            XCTFail("Expected invalid PDF failure")
        } catch {
            XCTAssertEqual(error as? APIError, .invalidResponse)
        }
    }

    func testEPUBRequiresZipSignature() async {
        let repository = repository { request in
            (Data("not a zip".utf8), Self.response(request, contentType: "application/epub+zip"))
        }

        do {
            _ = try await repository.epubDocument(fileID: UUID())
            XCTFail("Expected invalid EPUB failure")
        } catch {
            XCTAssertEqual(error as? APIError, .invalidResponse)
        }
    }

    func testEPUBAcceptsCanonicalContentTypeAndZipSignature() async throws {
        let repository = repository { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/epub+zip, application/json")
            return (
                Data([0x50, 0x4b, 0x03, 0x04, 0x00]),
                Self.response(request, contentType: "application/epub+zip")
            )
        }

        let data = try await repository.epubDocument(fileID: UUID())
        XCTAssertTrue(data.starts(with: Data([0x50, 0x4b, 0x03, 0x04])))
    }

    func testPageImageAcceptsValidImagePayload() async throws {
        let repository = repository { request in
            return (Data([0xff, 0xd8, 0xff]), Self.response(request, contentType: "image/jpeg"))
        }

        let data = try await repository.pageImage(fileID: UUID(), page: -9, width: 9_000)
        XCTAssertEqual(data, Data([0xff, 0xd8, 0xff]))
    }

    func testReadingPositionUsesIdempotentPutAndPrivacyResponse() async throws {
        let repository = repository { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["position_type"] as? String, "page")
            XCTAssertEqual(json["position_value"] as? String, "7")
            XCTAssertEqual(json["progress_percent"] as? Int, 35)
            return (
                Data(#"{"position":null,"recorded":false}"#.utf8),
                Self.response(request, contentType: "application/json")
            )
        }

        let recorded = try await repository.savePosition(
            fileID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            positionType: "page",
            positionValue: "7",
            progressPercent: 35,
            totalPages: 20
        )

        XCTAssertFalse(recorded)
    }

    private func repository(
        handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
    ) -> LiveReaderRepository {
        LiveReaderRepository(
            client: BeryndaAPIClient(
                baseURL: URL(string: "https://berynda.org/api/v1/")!,
                transport: ReaderStubTransport(handler: handler)
            )
        )
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private static func response(_ request: URLRequest, contentType: String) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        )!
    }
}
