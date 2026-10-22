import BeryndaCore
import SwiftUI

/// «Безпека» in the signed-in profile: the password and account deletion.
struct AccountSecuritySection: View {
    @ObservedObject var account: AccountViewModel
    let profile: UserProfile

    var body: some View {
        Section("Безпека") {
            NavigationLink(profile.hasPassword ? "Змінити пароль" : "Встановити пароль") {
                PasswordChangeView(account: account)
            }
            .accessibilityIdentifier("profile.security.password")
            NavigationLink {
                AccountDeletionView(account: account)
            } label: {
                Text("Видалити обліковий запис")
                    .foregroundStyle(.red)
            }
            .accessibilityIdentifier("profile.security.delete")
        }
    }
}

struct PasswordChangeView: View {
    @StateObject private var model: AccountSecurityViewModel

    init(account: AccountViewModel) {
        _model = StateObject(wrappedValue: AccountSecurityViewModel(account: account))
    }

    var body: some View {
        Form {
            if model.needsPasswordSetup {
                setupSection
            } else {
                changeSection
            }
            if let error = model.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("security.error")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(BeryndaColor.paper)
        .navigationTitle(model.needsPasswordSetup ? "Встановити пароль" : "Змінити пароль")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var changeSection: some View {
        Section {
            SecureField("Поточний пароль", text: $model.currentPassword)
                .textContentType(.password)
                .accessibilityIdentifier("security.current-password")
            SecureField("Новий пароль", text: $model.newPassword)
                .textContentType(.newPassword)
                .accessibilityIdentifier("security.new-password")
            SecureField("Повторіть новий пароль", text: $model.repeatedPassword)
                .textContentType(.newPassword)
                .accessibilityIdentifier("security.repeat-password")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let problem = model.passwordFormProblem {
                    Text(problem).foregroundStyle(.red)
                }
                ForEach(model.newPasswordMessages, id: \.self) { message in
                    Text(message).foregroundStyle(.red)
                }
                Text("Після зміни пароля інші пристрої доведеться увійти знову.")
            }
            .accessibilityIdentifier("security.password-hint")
        }

        Section {
            Button {
                Task { await model.changePassword() }
            } label: {
                HStack {
                    Text("Змінити пароль")
                    if model.isBusy {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!model.canChangePassword)
            .accessibilityIdentifier("security.change-password")
            if model.passwordChanged {
                Label("Пароль змінено.", systemImage: "checkmark.circle")
                    .foregroundStyle(BeryndaColor.accent)
                    .accessibilityIdentifier("security.password-changed")
            }
        }
    }

    @ViewBuilder
    private var setupSection: some View {
        Section {
            Text("Ви входите через Apple або Google, тож пароля в цього облікового запису ще немає. Надішлемо лист із посиланням, за яким його можна встановити.")
            if let email = model.email {
                LabeledContent("Електронна адреса", value: email)
            }
            Button("Надіслати лист") {
                Task { await model.sendPasswordSetupEmail() }
            }
            .disabled(model.isBusy || model.setupEmailSentTo != nil)
            .accessibilityIdentifier("security.send-setup-email")
            if let sentTo = model.setupEmailSentTo {
                Label("Лист надіслано на \(sentTo).", systemImage: "envelope")
                    .foregroundStyle(BeryndaColor.accent)
            }
        }
    }
}

/// Says plainly what goes and what stays, asks once more in a centred alert,
/// then re-checks the reader's identity with a method the account has.
struct AccountDeletionView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var account: AccountViewModel
    @StateObject private var model: AccountSecurityViewModel
    @StateObject private var apple = AppleSignInCoordinator()
    @State private var pendingMethod: ReauthenticationMethod?

    init(account: AccountViewModel) {
        self.account = account
        _model = StateObject(wrappedValue: AccountSecurityViewModel(account: account))
    }

    var body: some View {
        Form {
            Section("Буде видалено") {
                Label("Ваші списки й закладки", systemImage: "bookmark")
                Label("Позиції читання та історія переглядів", systemImage: "clock.arrow.circlepath")
                Label("Збережені колекції", systemImage: "square.stack")
                Label("Способи входу: пароль, Apple, Google", systemImage: "key")
            }
            Section {
                Label("Файли, які ви опублікували в бібліотеці", systemImage: "doc.text")
                Label("Сторінки авторів, які ви підтвердили як свої", systemImage: "person.text.rectangle")
            } header: {
                Text("Залишиться")
            } footer: {
                Text("Опубліковане залишається доступним читачам, але більше не пов’язане з вашим обліковим записом. Видалення не можна скасувати.")
            }

            Section {
                ForEach(model.deletionMethods, id: \.self) { method in
                    methodRow(method)
                }
                if model.isBusy { ProgressView().frame(maxWidth: .infinity) }
            } header: {
                Text("Підтвердьте, що це ви")
            } footer: {
                if model.deletionMethods == [.apple] {
                    Text("Обліковий запис пов’язано з Apple, тому видалення підтверджується лише через Apple.")
                }
            }
            .disabled(model.isBusy)

            if let error = model.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("security.error")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(BeryndaColor.paper)
        .navigationTitle("Видалення облікового запису")
        .navigationBarTitleDisplayMode(.inline)
        .task { await account.loadSocialProviders() }
        .alert(
            "Видалити обліковий запис?",
            isPresented: Binding(
                get: { pendingMethod != nil },
                set: { if !$0 { pendingMethod = nil } }
            ),
            presenting: pendingMethod
        ) { method in
            Button("Видалити", role: .destructive) {
                Task { await delete(with: method) }
            }
            .accessibilityIdentifier("security.delete-confirm")
            Button("Скасувати", role: .cancel) {}
        } message: { _ in
            Text("Списки, закладки й історію читання буде втрачено назавжди.")
        }
    }

    @ViewBuilder
    private func methodRow(_ method: ReauthenticationMethod) -> some View {
        switch method {
        case .password:
            SecureField("Поточний пароль", text: $model.deletionPassword)
                .textContentType(.password)
                .accessibilityIdentifier("security.delete-password")
            Button("Видалити обліковий запис", role: .destructive) {
                pendingMethod = .password
            }
            .disabled(!model.canDeleteWithPassword)
            .accessibilityIdentifier("security.delete-with-password")
        case .apple:
            AppleSignInButton { pendingMethod = .apple }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .accessibilityIdentifier("security.delete-with-apple")
        case .google:
            if googleAvailable {
                Button("Підтвердити через Google", role: .destructive) {
                    pendingMethod = .google
                }
                .accessibilityIdentifier("security.delete-with-google")
            }
        }
    }

    private var googleAvailable: Bool {
        let configuration = account.socialProviders
        return configuration.googleEnabled
            && configuration.googleIOSClientID != nil
            && configuration.googleServerClientID != nil
    }

    private func delete(with method: ReauthenticationMethod) async {
        let deleted: Bool
        switch method {
        case .password:
            deleted = await model.deleteWithPassword()
        case .apple:
            deleted = await model.deleteWithSocial(.apple) { challenge in
                try await apple.reauthorize(challenge: challenge, window: try SocialIdentityPrompt.keyWindow())
            }
        case .google:
            let configuration = account.socialProviders
            deleted = await model.deleteWithSocial(.google) { challenge in
                let token = try await SocialIdentityPrompt.googleIdentityToken(
                    challenge: challenge,
                    configuration: configuration,
                    window: try SocialIdentityPrompt.keyWindow()
                )
                return SocialReauthentication(
                    provider: .google,
                    challengeID: challenge.challengeID,
                    identityToken: token,
                    authorizationCode: nil
                )
            }
        }
        guard deleted else { return }
        dismiss()
        await environment.accountWasDeleted()
    }
}
