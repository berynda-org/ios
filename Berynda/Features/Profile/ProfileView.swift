import BeryndaCore
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @AppStorage("appearance.mode") private var appearanceMode = "system"
    @AppStorage(AccountViewModel.interfaceLanguageKey) private var interfaceLanguage = "uk"
    @State private var showsAuthentication = false
    @State private var showsEditor = false

    var body: some View {
        ProfileContent(
            account: environment.account,
            appearanceMode: $appearanceMode,
            interfaceLanguage: $interfaceLanguage,
            showsAuthentication: $showsAuthentication,
            showsEditor: $showsEditor
        )
    }
}

private struct ProfileContent: View {
    @ObservedObject var account: AccountViewModel
    @Binding var appearanceMode: String
    @Binding var interfaceLanguage: String
    @Binding var showsAuthentication: Bool
    @Binding var showsEditor: Bool

    var body: some View {
        List {
            if account.state == .authenticated, let profile = account.profile {
                Section("Обліковий запис") {
                    LabeledContent("Ім’я", value: profile.displayName ?? "—")
                    LabeledContent("Електронна адреса", value: profile.email)
                    Button("Редагувати профіль") { showsEditor = true }
                }
            } else {
                Section {
                    BeryndaEmptyState(
                        title: account.state == .expired ? "Сеанс завершився" : "Увійдіть до Беринди",
                        message: "Обліковий запис синхронізує списки та місце читання між пристроями.",
                        systemImage: "person.crop.circle"
                    )
                    Button("Увійти або зареєструватися") { showsAuthentication = true }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("profile.authenticate")
                }
            }

            Section("Вигляд") {
                Picker("Оформлення", selection: $appearanceMode) {
                    Text("Як на пристрої").tag("system")
                    Text("Світле").tag("light")
                    Text("Темне").tag("dark")
                }
                Picker("Мова", selection: $interfaceLanguage) {
                    Text("Українська").tag("uk")
                    Text("English").tag("en")
                }
                .onChange(of: interfaceLanguage) { _, language in
                    // The stored value is seeded from the profile on sign-in, so
                    // only a change the reader actually made reaches the server.
                    guard account.state == .authenticated,
                          account.profile?.uiLanguage != language else { return }
                    Task { _ = await account.updateProfile(ProfileUpdate(uiLanguage: language)) }
                }
            }

            if account.state == .authenticated, let profile = account.profile {
                Section("Конфіденційність") {
                    Toggle(
                        "Зберігати історію читання",
                        isOn: Binding(
                            get: { profile.readingHistoryEnabled },
                            set: { enabled in
                                var settings = profile.privacySettings
                                settings["reading_history_enabled"] = enabled
                                Task {
                                    _ = await account.updateProfile(
                                        ProfileUpdate(privacySettings: settings)
                                    )
                                }
                            }
                        )
                    )
                    Text("Після вимкнення сервер видаляє збережені позиції читання.")
                        .font(.footnote)
                        .foregroundStyle(BeryndaColor.mutedInk)
                }

                Section("Сховище") {
                    LabeledContent("Завантажені видання", value: "Немає")
                    Text("Тимчасові файли видання видаляються після закриття читача.")
                        .font(.footnote)
                        .foregroundStyle(BeryndaColor.mutedInk)
                }

                Section {
                    Button("Вийти", role: .destructive) { Task { await account.signOut() } }
                        .accessibilityIdentifier("profile.sign-out")
                }
            }

            Section("Беринда") {
                Link(destination: AppConfiguration.supportURL) {
                    Label("Відкрити сайт", systemImage: "safari")
                }
                Link(destination: AppConfiguration.privacyURL) {
                    Label("Конфіденційність", systemImage: "hand.raised")
                }
            }

            if let error = account.errorMessage {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(BeryndaColor.paper)
        .navigationTitle("Профіль")
        .accessibilityIdentifier("profile_screen")
        .sheet(isPresented: $showsAuthentication) {
            AuthenticationView(account: account)
        }
        .sheet(isPresented: $showsEditor) {
            if let profile = account.profile {
                ProfileEditorView(account: account, profile: profile)
            }
        }
        .task {
            if account.state == .authenticated, account.profile == nil {
                await account.loadProfile()
            }
        }
    }
}

private struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var account: AccountViewModel
    @State private var displayName: String
    @State private var bio: String
    @State private var institutionName: String

    init(account: AccountViewModel, profile: UserProfile) {
        self.account = account
        _displayName = State(initialValue: profile.displayName ?? "")
        _bio = State(initialValue: profile.bio ?? "")
        _institutionName = State(initialValue: profile.institutionName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Ім’я", text: $displayName)
                TextField("Установа", text: $institutionName)
                TextField("Про себе", text: $bio, axis: .vertical)
                    .lineLimit(3...8)
            }
            .navigationTitle("Редагувати профіль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Зберегти") {
                        Task {
                            let saved = await account.updateProfile(
                                ProfileUpdate(
                                    displayName: displayName,
                                    bio: bio,
                                    institutionName: institutionName
                                )
                            )
                            if saved { dismiss() }
                        }
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
