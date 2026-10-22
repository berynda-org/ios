import BeryndaCore
import SwiftUI

struct AuthenticationLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var account: AccountViewModel
    let route: AppRoute
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var localError: String?
    @State private var showsSignIn = false

    init(route: AppRoute, account: AccountViewModel) {
        self.route = route
        self.account = account
    }

    var body: some View {
        NavigationStack {
            Form {
                switch route {
                case .confirmEmail:
                    emailConfirmationContent
                case .resetPassword:
                    passwordResetContent
                case .work, .reader:
                    BeryndaEmptyState(
                        title: "Посилання недоступне",
                        message: "Це посилання не належить до облікового запису.",
                        systemImage: "link.badge.plus"
                    )
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .announcesChanges(of: localError ?? account.errorMessage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрити") { dismiss() }
                }
            }
            .sheet(isPresented: $showsSignIn) {
                AuthenticationView(account: account)
            }
            .task { await confirmEmailIfNeeded() }
        }
    }

    @ViewBuilder
    private var emailConfirmationContent: some View {
        if account.isBusy {
            Section { ProgressView("Підтверджуємо адресу…") }
        } else if account.emailConfirmationComplete {
            successSection(
                title: "Адресу підтверджено",
                message: "Тепер ви можете увійти до Беринди."
            )
        } else {
            failureSection(
                account.errorMessage ?? L("Посилання недійсне або вже прострочене.")
            )
        }
    }

    @ViewBuilder
    private var passwordResetContent: some View {
        if account.passwordResetComplete {
            successSection(
                title: "Пароль оновлено",
                message: "Усі попередні сеанси завершено. Увійдіть з новим паролем."
            )
        } else {
            Section("Новий пароль") {
                SecureField("Пароль", text: $password)
                    .textContentType(.newPassword)
                SecureField("Повторіть пароль", text: $passwordConfirmation)
                    .textContentType(.newPassword)
                Button("Оновити пароль") { submitPasswordReset() }
                    .disabled(account.isBusy)
            }
            if account.isBusy {
                Section { ProgressView("Оновлюємо пароль…") }
            }
            if let message = localError ?? account.errorMessage {
                failureSection(message)
            }
        }
    }

    @ViewBuilder
    private func successSection(title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        Section {
            Label(title, systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(BeryndaColor.accent)
            Text(message)
            Button("Увійти") { showsSignIn = true }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func failureSection(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    private var title: String {
        switch route {
        case .confirmEmail: L("Підтвердження пошти")
        case .resetPassword: L("Новий пароль")
        case .work, .reader: L("Посилання")
        }
    }

    private func confirmEmailIfNeeded() async {
        guard case let .confirmEmail(token) = route,
              !account.emailConfirmationComplete,
              !account.isBusy
        else { return }
        _ = await account.confirmEmail(token: token)
    }

    private func submitPasswordReset() {
        localError = passwordValidationError
        guard localError == nil,
              case let .resetPassword(uid, token) = route
        else { return }
        Task {
            _ = await account.confirmPasswordReset(
                uid: uid,
                token: token,
                newPassword: password
            )
            password = ""
            passwordConfirmation = ""
        }
    }

    private var passwordValidationError: String? {
        guard password.count >= 8 else {
            return L("Пароль має містити щонайменше 8 символів.")
        }
        guard password == passwordConfirmation else { return L("Паролі не збігаються.") }
        return nil
    }
}
