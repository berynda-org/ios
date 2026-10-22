import Foundation
import XCTest
import BeryndaCore
@testable import Berynda

private actor RecordingFeedbackRepository: FeedbackRepository {
    private let failure: (any Error)?
    private(set) var submissions: [FeedbackSubmission] = []

    init(failure: (any Error)? = nil) {
        self.failure = failure
    }

    func submit(_ submission: FeedbackSubmission) async throws -> FeedbackReceipt {
        submissions.append(submission)
        if let failure { throw failure }
        return FeedbackReceipt(ok: true, id: "1")
    }
}

/// Profile → «Відгук і підтримка»: what is sent signed in and signed out,
/// what is refused before sending, and how server refusals read.
@MainActor
final class FeedbackViewModelTests: XCTestCase {
    private let context = FeedbackAppContext(
        appVersion: "0.1.0 (1)",
        osVersion: "iOS 26.2",
        deviceModel: "iPhone17,1",
        locale: "uk-UA"
    )

    private func makeModel(
        _ kind: FeedbackViewModel.Kind,
        signedIn: Bool,
        repository: RecordingFeedbackRepository = RecordingFeedbackRepository()
    ) -> FeedbackViewModel {
        let fixed = self.context
        return FeedbackViewModel(kind: kind, repository: repository, isSignedIn: signedIn, context: { fixed })
    }

    func testSignedInRatingIsSentWithoutContactDetails() async {
        let repository = RecordingFeedbackRepository()
        let model = makeModel(.rating, signedIn: true, repository: repository)
        model.rating = 4
        model.message = "Дуже зручно"
        model.email = "ignored@example.org"
        await model.send()

        XCTAssertTrue(model.didSend)
        XCTAssertNil(model.errorMessage)
        let sent = await repository.submissions
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.topic, .appFeedback)
        XCTAssertEqual(sent.first?.rating, 4)
        XCTAssertNil(sent.first?.senderEmail, "The server fills in a signed-in reader's email")
        XCTAssertEqual(sent.first?.deviceModel, "iPhone17,1")
    }

    func testRatingIsRequiredBeforeAnythingIsSent() async {
        let repository = RecordingFeedbackRepository()
        let model = makeModel(.rating, signedIn: false, repository: repository)
        await model.send()

        XCTAssertFalse(model.didSend)
        XCTAssertEqual(model.errorMessage, FeedbackViewModel.message(for: .ratingRequired))
        let sent = await repository.submissions
        XCTAssertTrue(sent.isEmpty)
    }

    func testAnonymousSupportNeedsAReplyAddress() async {
        let repository = RecordingFeedbackRepository()
        let model = makeModel(.support, signedIn: false, repository: repository)
        model.message = "Книжка не відкривається офлайн."
        await model.send()
        XCTAssertEqual(model.errorMessage, FeedbackViewModel.message(for: .emailRequired))

        model.email = "reader@example.org"
        await model.send()
        XCTAssertTrue(model.didSend)
        let sent = await repository.submissions
        XCTAssertEqual(sent.first?.topic, .appSupport)
        XCTAssertEqual(sent.first?.senderEmail, "reader@example.org")
        XCTAssertNil(sent.first?.rating)
    }

    func testRateLimitReadsAsAFriendlyMessage() async {
        let repository = RecordingFeedbackRepository(
            failure: APIError.rateLimited(retryAfter: nil, context: APIErrorContext(code: "RATE_LIMITED"))
        )
        let model = makeModel(.support, signedIn: true, repository: repository)
        model.message = "Книжка не відкривається офлайн."
        await model.send()

        XCTAssertFalse(model.didSend)
        XCTAssertEqual(
            model.errorMessage,
            L("Ви вже надіслали кілька повідомлень. Спробуйте знову приблизно за годину.")
        )
    }

    func testValidationRefusalFromTheServerAsksToCheckTheForm() async {
        let repository = RecordingFeedbackRepository(
            failure: APIError.server(status: 400, context: APIErrorContext(code: "VALIDATION_ERROR"))
        )
        let model = makeModel(.rating, signedIn: true, repository: repository)
        model.rating = 5
        await model.send()
        XCTAssertEqual(model.errorMessage, L("Перевірте введені дані й спробуйте ще раз."))
    }

    func testDeviceContextIsFilledIn() {
        let context = FeedbackViewModel.currentContext()
        XCTAssertEqual(context.platform, "ios")
        XCTAssertTrue(context.osVersion.hasPrefix("iOS "), context.osVersion)
        XCTAssertTrue(context.appVersion.contains("("), context.appVersion)
        XCTAssertFalse(context.deviceModel.isEmpty)
        XCTAssertTrue(["uk-UA", "en-US"].contains(context.locale))
    }
}
