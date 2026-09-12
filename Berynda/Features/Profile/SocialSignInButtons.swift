import AuthenticationServices
import BeryndaCore
import GoogleSignIn
import GoogleSignInSwift
import SwiftUI

struct SocialSignInButtons: View {
    @ObservedObject var account: AccountViewModel
    var linking = false
    var onSuccess: () async -> Void = {}
    @State private var configuration = SocialProviderConfiguration.disabled
    @State private var linked = false
    @StateObject private var apple = AppleSignInCoordinator()

    var body: some View {
        Group {
            if configuration.appleEnabled || googleAvailable {
                Section(linking ? "Під’єднати спосіб входу" : "Швидкий вхід") {
                    if configuration.appleEnabled {
                        AppleSignInButton { begin(.apple) }
                            .frame(height: 48)
                            .accessibilityIdentifier("auth.apple")
                    }
                    if googleAvailable {
                        GoogleSignInButton { begin(.google) }
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
        .task { configuration = (try? await account.socialConfiguration()) ?? .disabled }
    }

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
                guard let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .filter({ $0.activationState == .foregroundActive })
                    .flatMap(\.windows).first(where: \.isKeyWindow) else {
                    throw SessionError.unavailable
                }
                if provider == .apple {
                    return try await apple.authorize(challenge: challenge, window: window)
                }
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
                    return SocialCredential(provider: .google, challengeID: challenge.challengeID, identityToken: token)
                } catch let error as NSError where error.domain == kGIDSignInErrorDomain && error.code == -5 {
                    throw CancellationError()
                }
            }
            if success {
                linked = linking
                await onSuccess()
            }
        }
    }
}

private struct AppleSignInButton: UIViewRepresentable {
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

@MainActor
private final class AppleSignInCoordinator: NSObject, ObservableObject,
    ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<SocialCredential, Error>?
    private var challengeID: UUID?
    private var window: UIWindow?
    private var controller: ASAuthorizationController?

    func authorize(challenge: SocialChallenge, window: UIWindow) async throws -> SocialCredential {
        guard continuation == nil else { throw SessionError.unavailable }
        self.window = window
        challengeID = challenge.challengeID
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
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
        finish(.success(SocialCredential(provider: .apple, challengeID: challengeID,
                                         identityToken: token, displayName: name)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if (error as? ASAuthorizationError)?.code == .canceled { finish(.failure(CancellationError())) }
        else { finish(.failure(SessionError.socialVerificationFailed)) }
    }

    private func finish(_ result: Result<SocialCredential, Error>) {
        let pending = continuation
        continuation = nil; controller = nil; window = nil; challengeID = nil
        pending?.resume(with: result)
    }
}
