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
            localStorage: environment.localStorage,
            appearanceMode: $appearanceMode,
            interfaceLanguage: $interfaceLanguage,
            showsAuthentication: $showsAuthentication,
            showsEditor: $showsEditor
        )
    }
}

private struct ProfileContent: View {
    @ObservedObject var account: AccountViewModel
    let localStorage: LocalStorageSummary
    @Binding var appearanceMode: String
    @Binding var interfaceLanguage: String
    @Binding var showsAuthentication: Bool
    @Binding var showsEditor: Bool
    /// `nil` while the summary is being measured or cleared.
    @State private var storageUsage: LocalStorageUsage?
    @State private var confirmsStorageClear = false

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
            }

            // Shown signed out as well: an anonymous reader's positions and
            // history are kept on this device just the same, and signing out
            // is how a signed-in reader clears them, not an anonymous one.
            Section("Сховище") {
                if let usage = storageUsage {
                    LabeledContent("Позиції читання", value: Self.bytes(usage.readingPositionsBytes))
                    LabeledContent("Нещодавно переглянуті", value: Self.bytes(usage.recentlyViewedBytes))
                    LabeledContent("Залишки файлів читача", value: Self.bytes(usage.readerTemporaryBytes))
                    LabeledContent("Разом", value: Self.bytes(usage.totalBytes))
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("profile.storage.total")
                } else {
                    HStack {
                        Text("Вимірюємо…")
                            .foregroundStyle(BeryndaColor.mutedInk)
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                    .accessibilityIdentifier("profile.storage.measuring")
                }
                Text(
                    "Тимчасові файли видання видаляються після закриття читача; тут показано лише те, що лишилося. Налаштування вигляду й читача займають кілька байтів і не очищаються."
                )
                .font(.footnote)
                .foregroundStyle(BeryndaColor.mutedInk)
                Button("Очистити локальні дані", role: .destructive) { confirmsStorageClear = true }
                    .disabled(storageUsage == nil)
                    .accessibilityIdentifier("profile.storage.clear")
                    .confirmationDialog(
                        "Очистити локальні дані?",
                        isPresented: $confirmsStorageClear,
                        titleVisibility: .visible
                    ) {
                        Button("Очистити", role: .destructive) {
                            Task { await clearLocalStorage() }
                        }
                        Button("Скасувати", role: .cancel) {}
                    } message: {
                        Text(
                            "Буде видалено збережені на цьому пристрої позиції читання, історію переглянутих творів і залишки тимчасових файлів. Вхід і налаштування збережуться."
                        )
                    }
            }

            if account.state == .authenticated, account.profile != nil {
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
        .task(id: account.state) {
            // Measured off the main thread by the actor, each time the tab
            // appears and again on sign-in or sign-out, since signing out
            // clears the reading history this section reports.
            storageUsage = await localStorage.measure()
        }
    }

    @MainActor
    private func clearLocalStorage() async {
        // Dropping the value shows the progress row and disables the button
        // until the actor has cleared and re-measured.
        storageUsage = nil
        storageUsage = await localStorage.clearCaches()
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        // "0 bytes" rather than "Zero KB": an empty category should read as a
        // measurement, not as a shrug.
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    private static func bytes(_ count: Int64) -> String {
        byteFormatter.string(fromByteCount: count)
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
