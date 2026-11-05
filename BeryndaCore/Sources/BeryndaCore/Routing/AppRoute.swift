import Foundation

public enum AppRoute: Equatable, Hashable, Sendable {
    case work(slug: String)
    case reader(fileID: UUID, page: Int?)
    case confirmEmail(token: String)
    case resetPassword(uid: String, token: String)

    public init?(url: URL, allowedHosts: Set<String> = ["berynda.org", "www.berynda.org"]) {
        let scheme = url.scheme?.lowercased()
        guard url.user == nil, url.password == nil else { return nil }
        if scheme == "https" {
            guard let host = url.host?.lowercased(), allowedHosts.contains(host),
                  url.port == nil || url.port == 443
            else { return nil }
        } else if scheme != "berynda" {
            return nil
        } else if url.port != nil {
            return nil
        }

        var parts = url.pathComponents.filter { $0 != "/" }
        if scheme == "berynda", let host = url.host, !host.isEmpty {
            parts.insert(host, at: 0)
        }
        if parts == ["auth", "confirm-email"],
           let token = Self.singleQueryValue(named: "token", from: url),
           Self.isSafeSecret(token, maximumLength: 4_096) {
            self = .confirmEmail(token: token)
            return
        }
        if parts == ["reset-password"],
           let uid = Self.singleQueryValue(named: "uid", from: url),
           let token = Self.singleQueryValue(named: "token", from: url),
           Self.isSafeSecret(uid, maximumLength: 512),
           Self.isSafeSecret(token, maximumLength: 2_048) {
            self = .resetPassword(uid: uid, token: token)
            return
        }

        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "works":
            let identifier = parts[1].lowercased()
            guard Self.isSafeWorkIdentifier(identifier) else { return nil }
            self = .work(slug: identifier)
        case "read":
            guard let id = UUID(uuidString: parts[1]) else { return nil }
            guard let page = Self.readerPage(from: url) else { return nil }
            self = .reader(fileID: id, page: page)
        default:
            return nil
        }
    }

    private static func isSafeWorkIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 200 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func singleQueryValue(named name: String, from url: URL) -> String? {
        let matches = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .filter { $0.name == name }
        guard matches.count == 1, let value = matches[0].value else { return nil }
        return value
    }

    private static func isSafeSecret(_ value: String, maximumLength: Int) -> Bool {
        guard !value.isEmpty, value.count <= maximumLength else { return false }
        return !value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
                || $0 == "/" || $0 == "?" || $0 == "#"
        }
    }

    /// Returns a doubly optional result: outer nil means malformed input;
    /// inner nil is a valid reader link without an explicit page.
    private static func readerPage(from url: URL) -> Int?? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let pageItems = items.filter { $0.name == "p" || $0.name == "page" }
        guard pageItems.count <= 1 else { return nil }
        guard let raw = pageItems.first?.value else {
            return pageItems.isEmpty ? .some(nil) : nil
        }
        guard let page = Int(raw), (1...1_000_000).contains(page) else { return nil }
        return .some(page)
    }
}
