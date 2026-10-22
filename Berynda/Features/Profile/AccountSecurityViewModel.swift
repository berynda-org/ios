import BeryndaCore
import Combine
import Foundation

/// State behind «Безпека»: changing (or first setting) the password and
/// deleting the account, with the server's refusals turned into what each
/// screen shows.
@MainActor
final class AccountSecurityViewModel: ObservableObject {
    @Published var currentPassword = ""
    @Published var newPassword = ""
    @Published var repeatedPassword = ""
    @Published var deletionPassword = ""
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    /// The server's own reasons a new password was refused, shown under it.
    @Published private(set) var newPasswordMessages: [String] = []
    @Published private(set) var passwordChanged = false
    /// The account has no password (Apple/Google sign-up); one is set
    /// through the reset email instead.
    @Published private(set) var needsPasswordSetup: Bool
    @Published private(set) var setupEmailSentTo: String?
    /// How deletion can be confirmed; narrowed by the server's answer.
    @Published private(set) var deletionMethods: [ReauthenticationMethod]

    static let minimumPasswordLength = 8

    private let account: AccountViewModel

    init(account: AccountViewModel) {
        self.account = account
        let profile = account.profile
        needsPasswordSetup = profile.map { !$0.hasPassword } ?? false
        deletionMethods = profile?.deletionMethods ?? [.password]
    }

    var email: String? { account.profile?.email }

    /// A problem the reader can fix before anything is sent, or `nil`.
    var passwordFormProblem: String? {
        guard !newPassword.isEmpty else { return nil }
        if newPassword.count < Self.minimumPasswordLength {
            return L("Новий пароль має містити щонайменше \(Self.minimumPasswordLength) символів.")
        }
        if !repeatedPassword.isEmpty, repeatedPassword != newPassword {
            return L("Паролі не збігаються.")
        }
        if !currentPassword.isEmpty, currentPassword == newPassword {
            return L("Новий пароль має відрізнятися від поточного.")
        }
        return nil
    }

    var canChangePassword: Bool {
        !isBusy
            && !currentPassword.isEmpty
            && !newPassword.isEmpty
            && repeatedPassword == newPassword
            && passwordFormProblem == nil
    }

    func changePassword() async {
        guard canChangePassword else { return }
        begin()
        defer { isBusy = false }
        do {
            try await account.changePassword(currentPassword: currentPassword, newPassword: newPassword)
            currentPassword = ""
            newPassword = ""
            repeatedPassword = ""
            passwordChanged = true
        } catch {
            await handle(error)
        }
    }

    /// The existing password-reset email, which is also how an Apple/Google
    /// account gets its first password: it proves the mailbox is theirs.
    func sendPasswordSetupEmail() async {
        guard let email, !isBusy else { return }
        begin()
        defer { isBusy = false }
        if await account.requestPasswordReset(email: email) {
            setupEmailSentTo = email
        } else {
            errorMessage = account.errorMessage ?? L("Не вдалося надіслати лист. Спробуйте ще раз.")
        }
    }

    var canDeleteWithPassword: Bool {
        !isBusy && deletionMethods.contains(.password) && !deletionPassword.isEmpty
    }

    /// `true` once the account is gone and the device has forgotten it.
    func deleteWithPassword() async -> Bool {
        guard canDeleteWithPassword else { return false }
        return await delete { _ in .password(deletionPassword) }
    }

    /// Asks the provider for a fresh identity bound to a reauthentication
    /// challenge, then deletes with it.
    func deleteWithSocial(
        _ provider: SocialProvider,
        authorize: (SocialChallenge) async throws -> SocialReauthentication
    ) async -> Bool {
        guard !isBusy else { return false }
        return await delete { account in
            let challenge = try await account.reauthenticationChallenge(provider: provider)
            let credential = try await authorize(challenge)
            try Task.checkCancellation()
            return .social(credential)
        }
    }

    private func delete(
        _ proof: (AccountViewModel) async throws -> AccountDeletionProof
    ) async -> Bool {
        begin()
        defer { isBusy = false }
        do {
            try await account.deleteAccount(proof: try await proof(account))
            deletionPassword = ""
            return true
        } catch {
            await handle(error)
            return false
        }
    }

    private func begin() {
        isBusy = true
        errorMessage = nil
        newPasswordMessages = []
        passwordChanged = false
    }

    private func handle(_ error: Error) async {
        if error is CancellationError { return }
        if let refusal = error as? AccountSecurityError {
            switch refusal {
            case let .passwordRejected(messages):
                newPasswordMessages = messages.isEmpty ? [refusal.localizedDescription] : messages
            case .noPassword:
                needsPasswordSetup = true
                errorMessage = refusal.localizedDescription
            case let .reauthenticationRequired(methods):
                if !methods.isEmpty {
                    deletionMethods = methods.contains(.apple) ? [.apple] : methods
                }
                deletionPassword = ""
                errorMessage = refusal.localizedDescription
            case .appleReauthenticationRequired:
                deletionMethods = [.apple]
                deletionPassword = ""
                errorMessage = refusal.localizedDescription
            default:
                errorMessage = refusal.localizedDescription
            }
            return
        }
        if let sessionError = error as? SessionError,
           sessionError == .expired || sessionError == .invalidToken {
            await account.syncSessionState()
            errorMessage = SessionError.expired.localizedDescription
            return
        }
        errorMessage = error.localizedDescription
    }
}
