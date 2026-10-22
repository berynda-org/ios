import AuthenticationServices
import BeryndaCore
import GoogleSignIn
import GoogleSignInSwift
import SwiftUI

struct SocialSignInButtons: View {
    @ObservedObject var account: AccountViewModel
    var linking = false
    var onSuccess: () async -> Void = {}
    @State private var linked = false
    @StateObject private var apple = AppleSignInCoordinator()

    var body: some View {
        Group {
            if account.socialProviderLoadState == .loading {
                Section { ProgressView("Завантажуємо способи входу…") }
            } else if account.socialProviderLoadState == .failed || account.socialProviderLoadState == .idle {
                Section("Швидкий вхід") {
                    Text("Не вдалося завантажити вхід через Apple та Google.")
                        .accessibilityIdentifier("auth.providers-error")
                    Button("Спробувати ще раз") {
                        Task { await account.loadSocialProviders() }
                    }
                    .accessibilityIdentifier("auth.providers-retry")
                }
            }
            if configuration.appleEnabled || googleAvailable {
                Section(linking ? "Під’єднати спосіб входу" : "Швидкий вхід") {
                    if configuration.appleEnabled {
                        AppleSignInButton { begin(.apple) }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .accessibilityIdentifier("auth.apple")
                    }
                    if googleAvailable {
                        GoogleSignInButton { begin(.google) }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .accessibilityIdentifier("auth.google")
                    }
                    if linked {
                        Label("Спосіб входу під’єднано", systemImage: "checkmark.circle")
                    }
                    if account.isBusy { ProgressView() }
                }
                .disabled(account.isBusy)
            }
        }
    }

    private var configuration: SocialProviderConfiguration { account.socialProviders }

    // The callback scheme is part of the signed app. Server configuration alone
    // cannot enable Google on an older build without that scheme.
    private var googleAvailable: Bool {
        guard configuration.googleEnabled, let client = configuration.googleIOSClientID,
              configuration.googleServerClientID != nil else { return false }
        let scheme = client.split(separator: ".").reversed().joined(separator: ".")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains(scheme) == true }
    }

    private func begin(_ provider: SocialProvider) {
        linked = false
        Task { @MainActor in
            let success = await account.socialSignIn(provider: provider, linking: linking) { challenge in
                let window = try SocialIdentityPrompt.keyWindow()
                if provider == .apple {
                    return try await apple.authorize(challenge: challenge, window: window)
                }
                let token = try await SocialIdentityPrompt.googleIdentityToken(
                    challenge: challenge,
                    configuration: configuration,
                    window: window
                )
                return SocialCredential(provider: .google, challengeID: challenge.challengeID, identityToken: token)
            }
            if success {
                linked = linking
                await onSuccess()
            }
        }
    }
}

/// The provider prompts shared by sign-in and the deletion re-check.
@MainActor
enum SocialIdentityPrompt {
    static func keyWindow() throws -> UIWindow {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive })
            .flatMap(\.windows).first(where: \.isKeyWindow) else {
            throw SessionError.unavailable
        }
        return window
    }

    /// A Google ID token carrying the challenge nonce.
    static func googleIdentityToken(
        challenge: SocialChallenge,
        configuration: SocialProviderConfiguration,
        window: UIWindow
    ) async throws -> String {
        guard let client = configuration.googleIOSClientID,
              let server = configuration.googleServerClientID,
              var presenter = window.rootViewController else { throw SessionError.unavailable }
        while let presented = presenter.presentedViewController { presenter = presented }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: client, serverClientID: server)
        // Berynda needs only the verified identity, not persistent Google access.
        defer { GIDSignIn.sharedInstance.signOut() }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter, hint: nil, additionalScopes: nil, nonce: challenge.nonce
            )
            guard let token = result.user.idToken?.tokenString else { throw SessionError.socialVerificationFailed }
            return token
        } catch let error as NSError where error.domain == kGIDSignInErrorDomain && error.code == -5 {
            throw CancellationError()
        }
    }
}

struct AppleSignInButton: UIViewRepresentable {
    var action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .continue, style: .black)
        button.cornerRadius = 8
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }
    func updateUIView(_ view: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
        view.isEnabled = context.environment.isEnabled
    }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

/// What Apple hands back: the identity token every flow sends, and the
/// one-time authorization code account deletion needs to revoke Apple tokens.
struct AppleAuthorization {
    let identityToken: String
    let authorizationCode: String?
    let displayName: String
}

@MainActor
final class AppleSignInCoordinator: NSObject, ObservableObject,
    ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleAuthorization, Error>?
    private var challengeID: UUID?
    private var window: UIWindow?
    private var controller: ASAuthorizationController?

    func authorize(challenge: SocialChallenge, window: UIWindow) async throws -> SocialCredential {
        let result = try await authorizeApple(challenge: challenge, window: window, scopes: [.fullName, .email])
        return SocialCredential(provider: .apple, challengeID: challenge.challengeID,
                                identityToken: result.identityToken, displayName: result.displayName)
    }

    /// Re-confirms the signed-in Apple ID. No name or email is asked for:
    /// only proof of control, plus the code the server revokes tokens with.
    func reauthorize(challenge: SocialChallenge, window: UIWindow) async throws -> SocialReauthentication {
        let result = try await authorizeApple(challenge: challenge, window: window, scopes: [])
        guard let code = result.authorizationCode else { throw SessionError.socialVerificationFailed }
        return SocialReauthentication(provider: .apple, challengeID: challenge.challengeID,
                                      identityToken: result.identityToken, authorizationCode: code)
    }

    private func authorizeApple(
        challenge: SocialChallenge,
        window: UIWindow,
        scopes: [ASAuthorization.Scope]
    ) async throws -> AppleAuthorization {
        guard continuation == nil else { throw SessionError.unavailable }
        self.window = window
        challengeID = challenge.challengeID
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = scopes
        request.nonce = challenge.nonce
        request.state = challenge.challengeID.uuidString
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            self.controller = controller
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        window ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let challengeID, credential.state == challengeID.uuidString,
              let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
            finish(.failure(SessionError.socialVerificationFailed)); return
        }
        let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) } ?? ""
        let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        finish(.success(AppleAuthorization(identityToken: token, authorizationCode: code, displayName: name)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if (error as? ASAuthorizationError)?.code == .canceled { finish(.failure(CancellationError())) }
        else { finish(.failure(SessionError.socialVerificationFailed)) }
    }

    private func finish(_ result: Result<AppleAuthorization, Error>) {
        let pending = continuation
        continuation = nil; controller = nil; window = nil; challengeID = nil
        pending?.resume(with: result)
    }
}
