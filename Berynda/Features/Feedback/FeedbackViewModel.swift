import BeryndaCore
import Foundation
import UIKit

/// «Оцінити застосунок» and «Написати в підтримку» in Profile → «Відгук і
/// підтримка». Both go to `POST contact/`; a signed-in reader's name and
/// email are filled in by the server from the account, so they are not asked
/// for or sent.
@MainActor
final class FeedbackViewModel: ObservableObject {
    enum Kind: Equatable {
        /// 1–5 stars and an optional comment.
        case rating
        /// A message that needs a reply.
        case support
    }

    let kind: Kind
    let isSignedIn: Bool
    @Published var rating: Int?
    @Published var message = ""
    @Published var name = ""
    @Published var email = ""
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var didSend = false

    private let repository: any FeedbackRepository
    private let context: @MainActor () -> FeedbackAppContext

    init(
        kind: Kind,
        repository: any FeedbackRepository,
        isSignedIn: Bool,
        context: @escaping @MainActor () -> FeedbackAppContext = { FeedbackViewModel.currentContext() }
    ) {
        self.kind = kind
        self.repository = repository
        self.isSignedIn = isSignedIn
        self.context = context
    }

    var maximumMessageLength: Int { FeedbackSubmission.maximumMessageLength }

    func send() async {
        guard !isSending, !didSend else { return }
        errorMessage = nil
        let submission: FeedbackSubmission
        do {
            submission = try makeSubmission()
        } catch let error as FeedbackValidationError {
            errorMessage = Self.message(for: error)
            return
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isSending = true
        defer { isSending = false }
        do {
            _ = try await repository.submit(submission)
            didSend = true
        } catch is CancellationError {
            return
        } catch APIError.rateLimited {
            errorMessage = L("Ви вже надіслали кілька повідомлень. Спробуйте знову приблизно за годину.")
        } catch let APIError.server(status, _) where status == 400 {
            errorMessage = L("Перевірте введені дані й спробуйте ще раз.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The request body, validated; exposed for tests.
    func makeSubmission() throws -> FeedbackSubmission {
        switch kind {
        case .rating:
            return try FeedbackSubmission.rating(
                rating,
                comment: message,
                name: isSignedIn ? nil : name,
                email: isSignedIn ? nil : email,
                context: context()
            )
        case .support:
            return try FeedbackSubmission.support(
                message: message,
                email: isSignedIn ? nil : email,
                isSignedIn: isSignedIn,
                context: context()
            )
        }
    }

    static func message(for error: FeedbackValidationError) -> String {
        switch error {
        case .ratingRequired:
            L("Оберіть оцінку від 1 до 5 зірок.")
        case let .messageTooShort(minimum):
            L("Повідомлення має містити щонайменше \(minimum) символів.")
        case let .messageTooLong(maximum):
            L("Повідомлення не може бути довшим за \(maximum) символів.")
        case .emailRequired:
            L("Вкажіть адресу, на яку відповісти.")
        case .emailInvalid:
            L("Введіть коректну електронну адресу.")
        case let .nameTooShort(minimum):
            L("Ім’я має містити щонайменше \(minimum) символи.")
        }
    }

    /// App and device facts the inbox shows next to the message. The device
    /// model is the hardware identifier (`iPhone16,2`), not the reader's
    /// device name.
    static func currentContext() -> FeedbackAppContext {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return FeedbackAppContext(
            appVersion: "\(version) (\(build))",
            osVersion: "iOS \(UIDevice.current.systemVersion)",
            deviceModel: hardwareModel(),
            locale: AppLanguage.current == .english ? "en-US" : "uk-UA"
        )
    }

    private static func hardwareModel() -> String {
        // The simulator reports the Mac's architecture; it names the
        // simulated model in its environment instead.
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: system.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return machine.isEmpty ? "iPhone" : machine
    }
}
