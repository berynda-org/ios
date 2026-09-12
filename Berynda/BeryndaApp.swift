import Foundation
import GoogleSignIn
import SwiftUI

@main
struct BeryndaApp: App {
    @StateObject private var environment: AppEnvironment

    @MainActor
    init() {
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
                .environmentObject(environment)
                .environmentObject(environment.networkMonitor)
                .tint(BeryndaColor.accent)
                .onOpenURL { url in
                    if !GIDSignIn.sharedInstance.handle(url) { environment.open(url) }
                }
        }
    }
}
