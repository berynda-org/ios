import Foundation

public actor SessionController: AuthorizationSession {
    private let tokenStore: any TokenStore
    private let authentication: any AuthenticationServing

    private var tokens: AuthTokens?
    private var didLoadTokens = false
    private var refreshTask: Task<AuthTokens, Error>?
    private var currentState: SessionState = .anonymous

    public init(
        tokenStore: any TokenStore,
        authentication: any AuthenticationServing
    ) {
        self.tokenStore = tokenStore
        self.authentication = authentication
    }

    public func state() -> SessionState {
        loadTokensIfNeeded()
        return currentState
    }

    public func accessToken() -> String? {
        loadTokensIfNeeded()
        return tokens?.access
    }

    @discardableResult
    public func signIn(email: String, password: String) async throws -> UserProfile {
        let session = try await authentication.login(email: email, password: password)
        return try await accept(session)
    }

    public func socialChallenge(provider: SocialProvider, linking: Bool) async throws -> SocialChallenge {
        guard linking else { return try await authentication.socialChallenge(provider: provider, accessToken: nil) }
        guard let token = accessToken() else { throw SessionError.expired }
        do { return try await authentication.socialChallenge(provider: provider, accessToken: token) }
        catch SessionError.expired {
            let fresh = try await refreshAccessToken(rejectedAccessToken: token)
            return try await authentication.socialChallenge(provider: provider, accessToken: fresh)
        }
    }

    public func signIn(_ credential: SocialCredential) async throws -> UserProfile {
        let session = try await authentication.socialLogin(credential)
        return try await accept(session)
    }

    public func link(_ credential: SocialCredential) async throws -> UserProfile {
        guard let token = accessToken() else { throw SessionError.expired }
        do { return try await authentication.linkSocialIdentity(credential, accessToken: token) }
        catch SessionError.expired {
            let fresh = try await refreshAccessToken(rejectedAccessToken: token)
            return try await authentication.linkSocialIdentity(credential, accessToken: fresh)
        }
    }

    public func reauthenticationChallenge(provider: SocialProvider) async throws -> SocialChallenge {
        try await withAccessToken { token in
            try await self.authentication.reauthenticationChallenge(provider: provider, accessToken: token)
        }
    }

    /// Changes the password and keeps this device signed in with the fresh
    /// pair the server returns; the old pair is already revoked.
    public func changePassword(currentPassword: String, newPassword: String) async throws {
        let rotated = try await withAccessToken { token in
            try await self.authentication.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword,
                accessToken: token
            )
        }
        do {
            try tokenStore.save(rotated)
        } catch {
            expireSession()
            throw SessionError.storage
        }
        tokens = rotated
        didLoadTokens = true
        currentState = .authenticated
    }

    /// Deletes the account, then forgets the session locally. No logout call
    /// follows: the server has already revoked every token of the account.
    public func deleteAccount(proof: AccountDeletionProof) async throws {
        try await withAccessToken { token in
            try await self.authentication.deleteAccount(proof: proof, accessToken: token)
        }
        clearLocalSession(state: .anonymous)
    }

    /// Runs an authenticated call, refreshing the access token once if the
    /// server reports it expired.
    private func withAccessToken<Value: Sendable>(
        _ operation: @Sendable (String) async throws -> Value
    ) async throws -> Value {
        guard let token = accessToken() else { throw SessionError.expired }
        do {
            return try await operation(token)
        } catch SessionError.expired {
            let fresh = try await refreshAccessToken(rejectedAccessToken: token)
            return try await operation(fresh)
        }
    }

    private func accept(_ session: AuthSession) async throws -> UserProfile {
        do {
            try tokenStore.save(session.tokens)
        } catch {
            try? await authentication.logout(
                accessToken: session.tokens.access,
                refreshToken: session.tokens.refresh
            )
            throw SessionError.storage
        }
        tokens = session.tokens
        didLoadTokens = true
        currentState = .authenticated
        return session.user
    }

    public func refreshAccessToken(rejectedAccessToken: String) async throws -> String {
        loadTokensIfNeeded()
        guard let current = tokens else { throw SessionError.expired }

        // Another request may already have refreshed while this 401 was in flight.
        if current.access != rejectedAccessToken {
            return current.access
        }

        let task: Task<AuthTokens, Error>
        if let existing = refreshTask {
            task = existing
        } else {
            let authentication = self.authentication
            let refreshToken = current.refresh
            let created = Task {
                try await authentication.refresh(refreshToken: refreshToken)
            }
            refreshTask = created
            task = created
        }

        let rotated: AuthTokens
        do {
            rotated = try await task.value
        } catch is CancellationError {
            refreshTask = nil
            throw CancellationError()
        } catch let error as SessionError where error == .expired || error == .invalidToken {
            refreshTask = nil
            expireSession()
            throw SessionError.expired
        } catch {
            refreshTask = nil
            throw error
        }

        if tokens?.access == rotated.access {
            refreshTask = nil
            return rotated.access
        }

        do {
            try tokenStore.save(rotated)
        } catch {
            refreshTask = nil
            expireSession()
            throw SessionError.storage
        }
        tokens = rotated
        currentState = .authenticated
        refreshTask = nil
        return rotated.access
    }

    public func signOut() async throws {
        loadTokensIfNeeded()
        let sessionToRevoke = tokens
        tokens = nil
        didLoadTokens = true
        currentState = .anonymous
        refreshTask?.cancel()
        refreshTask = nil
        let localClearFailed: Bool
        do {
            try tokenStore.clear()
            localClearFailed = false
        } catch {
            localClearFailed = true
        }

        if let sessionToRevoke {
            do {
                try await authentication.logout(
                    accessToken: sessionToRevoke.access,
                    refreshToken: sessionToRevoke.refresh
                )
            } catch SessionError.expired {
                // The logout endpoint requires a live access token. Rotate once so
                // an expired access token cannot leave the server refresh alive.
                if let rotated = try? await authentication.refresh(
                    refreshToken: sessionToRevoke.refresh
                ) {
                    try? await authentication.logout(
                        accessToken: rotated.access,
                        refreshToken: rotated.refresh
                    )
                }
            } catch {
                // Local logout is authoritative for the device. A network failure
                // cannot restore erased credentials; the server token expires.
            }
        }

        if localClearFailed { throw SessionError.storage }
    }

    public func markExpired() {
        expireSession()
    }

    private func loadTokensIfNeeded() {
        guard !didLoadTokens else { return }
        didLoadTokens = true
        do {
            tokens = try tokenStore.load()
            currentState = tokens == nil ? .anonymous : .authenticated
        } catch {
            // Do not delete an unreadable Keychain record. Anonymous access can
            // continue and a later explicit sign-in may replace the record.
            tokens = nil
            currentState = .anonymous
        }
    }

    private func expireSession() {
        clearLocalSession(state: .expired)
    }

    private func clearLocalSession(state: SessionState) {
        tokens = nil
        didLoadTokens = true
        currentState = state
        refreshTask?.cancel()
        refreshTask = nil
        try? tokenStore.clear()
    }
}
