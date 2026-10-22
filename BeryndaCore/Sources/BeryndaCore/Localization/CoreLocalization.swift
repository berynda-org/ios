import Foundation

/// Copy the package produces itself (API and sign-in errors, catalog
/// vocabulary, issue labels) is written in Ukrainian, the source language, and
/// passed through this hook. The app installs a translator that looks the
/// Ukrainian text up in its String Catalog; the package and its tests keep the
/// identity function, so they see the Ukrainian source.
public enum CoreLocalization {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var translator: @Sendable (String) -> String = { $0 }

    /// Replaces the translator. The app calls this once at launch.
    public static func install(_ translate: @escaping @Sendable (String) -> String) {
        lock.lock()
        defer { lock.unlock() }
        translator = translate
    }

    /// The translation of a Ukrainian source string.
    public static func string(_ key: String) -> String {
        lock.lock()
        let translate = translator
        lock.unlock()
        return translate(key)
    }

    /// A translated format string (`%@`, `%lld`) filled with `arguments`.
    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }
}
