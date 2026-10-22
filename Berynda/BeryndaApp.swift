import Foundation
import GoogleSignIn
import SwiftUI

@main
struct BeryndaApp: App {
    @StateObject private var environment: AppEnvironment
    /// Profile → «Мова». The window's content is rebuilt when it changes, so
    /// copy computed from `String`s (not only SwiftUI literals) switches too.
    @AppStorage(AppLanguage.storageKey) private var interfaceLanguage = AppLanguage.ukrainian.rawValue

    @MainActor
    init() {
        AppLanguage.installCoreTranslator()
        #if DEBUG
        let environment = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            ? AppEnvironment.uiTesting()
            : AppEnvironment.live()
        #else
        let environment = AppEnvironment.live()
        #endif
        _environment = StateObject(wrappedValue: environment)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, AppLanguage(code: interfaceLanguage).locale)
                .id(interfaceLanguage)
                .environmentObject(environment)
                .environmentObject(environment.networkMonitor)
                .tint(BeryndaColor.accent)
                .onOpenURL { url in
                    if !GIDSignIn.sharedInstance.handle(url) { environment.open(url) }
                }
        }
    }
}
