import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// How the app names itself to the Berynda API, so the server's traffic
/// reports can count iOS separately (`X-Berynda-Client: ios/<version>`, the
/// header the Android app already sends). Without it URLSession's default
/// User-Agent carries no device hint and the server had to guess.
public struct ClientIdentity: Sendable, Equatable {
    public static let headerName = "X-Berynda-Client"

    /// `ios/<version>`; the server accepts `[0-9A-Za-z.+-]{1,32}` after the
    /// slash and ignores anything else, so the version is cleaned to fit.
    public let headerValue: String
    public let userAgent: String

    public init(version: String, build: String?, systemVersion: String) {
        let version = Self.token(version) ?? "unknown"
        headerValue = "ios/\(version)"
        var agent = "Berynda-iOS/\(version)"
        var details: [String] = []
        if let build = build.flatMap(Self.token) { details.append(build) }
        if let system = Self.token(systemVersion) { details.append("iOS \(system)") }
        if !details.isEmpty { agent += " (\(details.joined(separator: "; ")))" }
        userAgent = agent
    }

    /// The running app's identity, read from its bundle.
    public static let current: ClientIdentity = {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return ClientIdentity(
            version: info["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info["CFBundleVersion"] as? String,
            systemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        )
    }()

    func apply(to request: inout URLRequest) {
        request.setValue(headerValue, forHTTPHeaderField: Self.headerName)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    }

    /// Keeps only characters the server's header pattern allows, capped at
    /// its 32-character limit; nil when nothing usable is left.
    static func token(_ raw: String) -> String? {
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz.+-")
        let cleaned = String(raw.filter { allowed.contains($0) }.prefix(32))
        return cleaned.isEmpty ? nil : cleaned
    }
}
