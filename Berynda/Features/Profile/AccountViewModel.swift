import BeryndaCore
import Combine
import Foundation

@MainActor
final class AccountViewModel: ObservableObject {
    @Published private(set) var state: SessionState = .anonymous
    @Published private(set) var profile: UserProfile?
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published var registrationEmail: String?
    @Published var passwordResetEmail: String?
    @Published private(set) var emailConfirmationComplete = false
    @Published private(set) var passwordResetComplete = false

    private let session: SessionController
    private let authentication: any AuthenticationServing
    private let repository: any AccountRepository
    private let localPositions: LocalReadingPositionStore
    private let recentlyViewed: RecentlyViewedStore
    private var didRestore = false

    /// `UserDefaults` key behind the interface-language picker. Seeded from the
    /// server profile so a signed-in reader's stored preference is not silently
    /// replaced by whatever this device happened to have.
    static let interfaceLanguageKey = "ui.language"

    init(
        session: SessionController,
        authentication: any AuthenticationServing,
        repository: any AccountRepository,
        localPositions: LocalReadingPositionStore,
        recentlyViewed: RecentlyViewedStore
    ) {
        self.session = session
        self.authentication = authentication
        self.repository = repository
        self.localPositions = localPositions
        self.recentlyViewed = recentlyViewed
    }

    func restore() async {
        guard !didRestore else { return }
        didRestore = true
        state = await session.state()
        guard state == .authenticated else { return }
        await loadProfile()
    }

    func signIn(email: String, password: String) async -> Bool {
        await perform {
            let user = try await session.signIn(email: email, password: password)
            apply(profile: user)
            state = .authenticated
            registrationEmail = nil
        }
    }

    func register(email: String, password: String, displayName: String) async -> Bool {
        await perform {
            emailConfirmationComplete = false
            let result = try await authentication.register(
                email: email,
                password: password,
                displayName: displayName
            )
            registrationEmail = result.requiresEmailConfirmation ? result.email : nil
        }
    }

    func requestPasswordReset(email: String) async -> Bool {
        await perform {
            passwordResetComplete = false
            try await authentication.requestPasswordReset(email: email)
            passwordResetEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func confirmEmail(token: String) async -> Bool {
        await perform {
            emailConfirmationComplete = false
            _ = try await authentication.confirmEmail(token: token)
            registrationEmail = nil
            emailConfirmationComplete = true
        }
    }

    func confirmPasswordReset(uid: String, token: String, newPassword: String) async -> Bool {
        await perform {
            passwordResetComplete = false
            try await authentication.confirmPasswordReset(
                uid: uid,
                token: token,
                newPassword: newPassword
            )
            if await session.state() == .authenticated {
                await session.markExpired()
                state = .expired
                profile = nil
                await clearLocalHistory()
            }
            passwordResetComplete = true
            passwordResetEmail = nil
        }
    }

    func loadProfile() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let loaded = try await repository.profile()
            apply(profile: loaded)
            state = .authenticated
        } catch {
            let current = await session.state()
            state = current
            if current != .authenticated { profile = nil }
            errorMessage = error.localizedDescription
        }
    }

    func updateProfile(_ update: ProfileUpdate) async -> Bool {
        await perform {
            profile = try await repository.updateProfile(update)
            state = .authenticated
            if update.privacySettings?["reading_history_enabled"] == false {
                await clearLocalHistory()
            }
        }
    }

    func signOut() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await session.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
        profile = nil
        state = .anonymous
        await clearLocalHistory()
    }

    /// Everything on this device that records what the reader opened. The two
    /// stores must always be dropped together: leaving one behind either
    /// hands one reader's history to the next account or keeps a shelf
    /// populated after the reader asked for no history at all.
    private func clearLocalHistory() async {
        await localPositions.clearAll()
        await recentlyViewed.clear()
    }

    private func apply(profile loaded: UserProfile) {
        profile = loaded
        UserDefaults.standard.set(loaded.uiLanguage, forKey: Self.interfaceLanguageKey)
    }

    private func perform(_ operation: () async throws -> Void) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await operation()
            return true
        } catch {
            errorMessage = error.localizedDescription
            state = await session.state()
            return false
        }
    }
}
