import SwiftUI

struct AuthenticationView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn
        case register

        var id: Self { self }
        var title: String { self == .signIn ? "Увійти" : "Реєстрація" }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var account: AccountViewModel
    private let onAuthenticated: () async -> Void
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var showsPasswordReset = false
    @State private var localError: String?

    init(
        account: AccountViewModel,
        onAuthenticated: @escaping () async -> Void = {}
    ) {
        self.account = account
        self.onAuthenticated = onAuthenticated
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Дія", selection: $mode) {
                    ForEach(Mode.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                SocialSignInButtons(account: account) {
                    await onAuthenticated()
                    dismiss()
                }

                if let confirmation = account.registrationEmail {
                    Section {
                        Label("Перевірте пошту", systemImage: "envelope.badge")
                            .font(.headline)
                        Text("Ми надіслали посилання для підтвердження на \(confirmation). Після підтвердження поверніться сюди та увійдіть.")
                            .font(.subheadline)
                    }
                }

                Section(mode == .signIn ? "Обліковий запис" : "Новий обліковий запис") {
                    if mode == .register {
                        TextField("Ім’я", text: $displayName)
                            .textContentType(.name)
                            .accessibilityIdentifier("auth.display-name")
                    }
                    TextField("Електронна адреса", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("auth.email")
                    SecureField("Пароль", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .accessibilityIdentifier("auth.password")
                    if mode == .register {
                        SecureField("Повторіть пароль", text: $passwordConfirmation)
                            .textContentType(.newPassword)
                            .accessibilityIdentifier("auth.password-confirmation")
                    }
                }

                if let message = localError ?? account.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(mode.title) { submit() }
                        .disabled(account.isBusy)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("auth.submit")
                    if account.isBusy { ProgressView().frame(maxWidth: .infinity) }
                }

                if mode == .signIn {
                    Button("Забули пароль?") { showsPasswordReset = true }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрити") { dismiss() }
                        .disabled(account.isBusy)
                }
            }
            .interactiveDismissDisabled(account.isBusy)
            .sheet(isPresented: $showsPasswordReset) {
                PasswordResetView(account: account, initialEmail: email)
            }
        }
    }

    private func submit() {
        localError = validationError
        guard localError == nil else { return }
        Task {
            let succeeded: Bool
            switch mode {
            case .signIn:
                succeeded = await account.signIn(email: email, password: password)
            case .register:
                succeeded = await account.register(
                    email: email,
                    password: password,
                    displayName: displayName
                )
            }
            if succeeded, mode == .signIn {
                await onAuthenticated()
                dismiss()
            }
        }
    }

    private var validationError: String? {
        guard email.contains("@") else { return "Введіть коректну електронну адресу." }
        guard password.count >= 8 else { return "Пароль має містити щонайменше 8 символів." }
        if mode == .register {
            guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "Введіть ім’я."
            }
            guard password == passwordConfirmation else { return "Паролі не збігаються." }
        }
        return nil
    }
}

private struct PasswordResetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var account: AccountViewModel
    @State private var email: String

    init(account: AccountViewModel, initialEmail: String) {
        self.account = account
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            Form {
                if account.passwordResetEmail != nil {
                    Label("Якщо адреса зареєстрована, лист з інструкціями вже надіслано.", systemImage: "checkmark.circle")
                } else {
                    TextField("Електронна адреса", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    Button("Надіслати інструкції") {
                        Task { _ = await account.requestPasswordReset(email: email) }
                    }
                    .disabled(!email.contains("@") || account.isBusy)
                }
            }
            .navigationTitle("Відновлення пароля")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
