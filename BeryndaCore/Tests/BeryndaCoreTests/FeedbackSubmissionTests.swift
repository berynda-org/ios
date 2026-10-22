import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import BeryndaCore

private actor ContactTransportStub: HTTPTransport {
    private let status: Int
    private let body: Data
    private(set) var requests: [URLRequest] = []

    init(status: Int, body: String) {
        self.status = status
        self.body = Data(body.utf8)
    }

    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (
            body,
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
        )
    }
}

/// «Відгук і підтримка»: what is validated before sending and what
/// `POST contact/` receives.
final class FeedbackSubmissionTests: XCTestCase {
    private let context = FeedbackAppContext(
        appVersion: "0.1.0 (7)",
        osVersion: "iOS 26.2",
        deviceModel: "iPhone16,2",
        locale: "uk-UA"
    )

    private func json(_ submission: FeedbackSubmission) throws -> [String: Any] {
        let data = try JSONEncoder().encode(submission)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testSignedInRatingLeavesNameAndEmailToTheServer() throws {
        let submission = try FeedbackSubmission.rating(5, comment: "  Дуже зручно \n", context: context)
        let body = try json(submission)
        XCTAssertEqual(body["topic"] as? String, "app_feedback")
        XCTAssertEqual(body["rating"] as? Int, 5)
        XCTAssertEqual(body["message"] as? String, "Дуже зручно")
        XCTAssertEqual(body["platform"] as? String, "ios")
        XCTAssertEqual(body["app_version"] as? String, "0.1.0 (7)")
        XCTAssertEqual(body["os_version"] as? String, "iOS 26.2")
        XCTAssertEqual(body["device_model"] as? String, "iPhone16,2")
        XCTAssertEqual(body["locale"] as? String, "uk-UA")
        XCTAssertNil(body["sender_name"])
        XCTAssertNil(body["sender_email"])
    }

    func testAnonymousRatingMayCarryContactDetails() throws {
        let body = try json(
            FeedbackSubmission.rating(3, comment: "", name: "Оля", email: " Olia@Example.org ", context: context)
        )
        XCTAssertEqual(body["sender_name"] as? String, "Оля")
        XCTAssertEqual(body["sender_email"] as? String, "olia@example.org")
        XCTAssertEqual(body["message"] as? String, "")
    }

    func testRatingIsRequiredAndBounded() {
        XCTAssertThrowsError(try FeedbackSubmission.rating(nil, comment: "", context: context)) {
            XCTAssertEqual($0 as? FeedbackValidationError, .ratingRequired)
        }
        XCTAssertThrowsError(try FeedbackSubmission.rating(6, comment: "", context: context)) {
            XCTAssertEqual($0 as? FeedbackValidationError, .ratingRequired)
        }
        let long = String(repeating: "а", count: 5_001)
        XCTAssertThrowsError(try FeedbackSubmission.rating(4, comment: long, context: context)) {
            XCTAssertEqual($0 as? FeedbackValidationError, .messageTooLong(maximum: 5_000))
        }
        XCTAssertThrowsError(try FeedbackSubmission.rating(4, comment: "", email: "not-an-email", context: context)) {
            XCTAssertEqual($0 as? FeedbackValidationError, .emailInvalid)
        }
        XCTAssertThrowsError(try FeedbackSubmission.rating(4, comment: "", name: "О", context: context)) {
            XCTAssertEqual($0 as? FeedbackValidationError, .nameTooShort(minimum: 2))
        }
    }

    func testSupportNeedsTenCharactersAndAReplyAddressWhenSignedOut() throws {
        XCTAssertThrowsError(
            try FeedbackSubmission.support(message: "Не працює", email: "a@b.org", isSignedIn: false, context: context)
        ) { XCTAssertEqual($0 as? FeedbackValidationError, .messageTooShort(minimum: 10)) }
        XCTAssertThrowsError(
            try FeedbackSubmission.support(message: "Книжка не відкривається", email: " ", isSignedIn: false, context: context)
        ) { XCTAssertEqual($0 as? FeedbackValidationError, .emailRequired) }

        let anonymous = try json(
            FeedbackSubmission.support(
                message: "Книжка не відкривається",
                email: "reader@example.org",
                isSignedIn: false,
                context: context
            )
        )
        XCTAssertEqual(anonymous["topic"] as? String, "app_support")
        XCTAssertEqual(anonymous["sender_email"] as? String, "reader@example.org")
        XCTAssertNil(anonymous["rating"], "Rating is forbidden for app_support")

        let signedIn = try json(
            FeedbackSubmission.support(message: "Книжка не відкривається", email: nil, isSignedIn: true, context: context)
        )
        XCTAssertNil(signedIn["sender_email"])
    }

    func testPlausibleEmailCheck() {
        XCTAssertTrue(FeedbackSubmission.isPlausibleEmail("reader@example.org"))
        XCTAssertFalse(FeedbackSubmission.isPlausibleEmail("reader@example"))
        XCTAssertFalse(FeedbackSubmission.isPlausibleEmail("@example.org"))
        XCTAssertFalse(FeedbackSubmission.isPlausibleEmail("reader@example."))
        XCTAssertFalse(FeedbackSubmission.isPlausibleEmail("a b@example.org"))
    }

    func testSubmitPostsToContactAndDecodesTheReceipt() async throws {
        let transport = ContactTransportStub(status: 201, body: #"{"ok": true, "id": "3f0c1d6e-0000-4000-8000-000000000001"}"#)
        let client = BeryndaAPIClient(baseURL: URL(string: "https://berynda.org/api/v1/")!, transport: transport)
        let receipt = try await LiveFeedbackRepository(client: client)
            .submit(FeedbackSubmission.rating(5, comment: "", context: context))
        XCTAssertEqual(receipt, FeedbackReceipt(ok: true, id: "3f0c1d6e-0000-4000-8000-000000000001"))

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://berynda.org/api/v1/contact/")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "Anonymous feedback carries no token")
        let body = try XCTUnwrap(request.httpBody)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(sent["topic"] as? String, "app_feedback")
    }

    func testRateLimitIsReportedAndNotRetried() async throws {
        let transport = ContactTransportStub(status: 429, body: #"{"code": "RATE_LIMITED"}"#)
        let client = BeryndaAPIClient(baseURL: URL(string: "https://berynda.org/api/v1/")!, transport: transport)
        do {
            _ = try await LiveFeedbackRepository(client: client)
                .submit(FeedbackSubmission.rating(5, comment: "", context: context))
            XCTFail("Expected a rate-limit error")
        } catch let APIError.rateLimited(_, context) {
            XCTAssertEqual(context.code, "RATE_LIMITED")
        }
        let count = await transport.requests.count
        XCTAssertEqual(count, 1, "A POST without an idempotency key is never repeated")
    }
}
