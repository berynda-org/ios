import BeryndaCore
import Foundation

/// The interface language picked in Profile → «Мова».
///
/// The app does not follow the device language: Ukrainian is the source
/// language and the default, and English is an explicit choice (stored under
/// `ui.language` and synced to the account's `ui_language`). Two lookups
/// follow the choice at runtime:
///
/// - SwiftUI literals (`Text("…")`, `Button("…")`, …) are `LocalizedStringKey`s
///   that SwiftUI resolves against the `locale` in the environment, which
///   `BeryndaApp` sets from this value at the root of the window.
/// - `String` copy (view-model messages, accessibility labels assembled in
///   code, the core package's errors) goes through `L(_:)`, which reads the
///   compiled String Catalog straight from the language's `.lproj` folder, so
///   it does not depend on the process-wide `Bundle.main` language that iOS
///   picks once at launch from the device settings.
///
/// The root view is rebuilt (`.id`) when the value changes, so copy computed
/// from `String`s is re-evaluated too.
enum AppLanguage: String, CaseIterable, Sendable {
    case ukrainian = "uk"
    case english = "en"

    /// `UserDefaults` key behind the picker. A launch argument
    /// (`-ui.language en`) overrides it, which is how UI tests force English.
    static let storageKey = "ui.language"

    static var current: AppLanguage {
        AppLanguage(code: UserDefaults.standard.string(forKey: storageKey))
    }

    /// Anything that is not English falls back to the source language.
    init(code: String?) {
        let normalized = (code ?? "").lowercased()
        self = normalized.hasPrefix("en") ? .english : .ukrainian
    }

    /// Also used to format numbers and dates in interpolated copy.
    var locale: Locale {
        switch self {
        case .ukrainian: Locale(identifier: "uk_UA")
        case .english: Locale(identifier: "en_US")
        }
    }

    /// The compiled catalog for this language (`uk.lproj` / `en.lproj` inside
    /// the app). Falls back to the main bundle if the folder is missing, in
    /// which case lookups return the Ukrainian key itself.
    var bundle: Bundle {
        if let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    /// The value sent as `Accept-Language`, so server-supplied copy (errors,
    /// restriction reasons) matches the interface.
    var acceptLanguage: String { rawValue }

    /// Points the core package's copy (API errors, catalog vocabulary) at the
    /// app's String Catalog. Called once at launch.
    static func installCoreTranslator() {
        CoreLocalization.install { key in
            AppLanguage.current.bundle.localizedString(forKey: key, value: key, table: nil)
        }
    }
}

/// Looks up `String` copy in the String Catalog in the language chosen in
/// Profile. Interpolations become format arguments exactly as in
/// `String(localized:)` (`Int` → `%lld`, `String` → `%@`).
func L(_ value: String.LocalizationValue) -> String {
    let language = AppLanguage.current
    return String(localized: value, bundle: language.bundle, locale: language.locale)
}
