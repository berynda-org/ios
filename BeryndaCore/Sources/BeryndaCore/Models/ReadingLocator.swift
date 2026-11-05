import Foundation

/// A reading position in a publication, in the shape both clients agree on.
///
/// The web reader stores an epub.js CFI and this client uses Readium, which
/// neither produces nor resolves a full CFI. A locator is what each can
/// express: every client writes the fields it knows and reads the field it
/// understands, falling back to `totalProgression` — which every renderer can
/// approximate — when it cannot use the others.
///
/// Encoded as the API's `position_type: "locator"`, whose `position_value` is
/// this object as compact JSON. Keys are snake_case to match the API.
public struct ReadingLocator: Codable, Hashable, Sendable {
    /// Resource within the publication.
    public let href: String?
    /// Progress within `href`, 0…1.
    public let progression: Double?
    /// Progress through the whole publication, 0…1.
    public let totalProgression: Double?
    /// An epub.js CFI, when the writing client could produce one. This client
    /// preserves it on round-trip but cannot resolve it.
    public let cfi: String?

    public init(
        href: String? = nil,
        progression: Double? = nil,
        totalProgression: Double? = nil,
        cfi: String? = nil
    ) {
        self.href = href
        self.progression = progression
        self.totalProgression = totalProgression
        self.cfi = cfi
    }

    enum CodingKeys: String, CodingKey {
        case href
        case progression
        case totalProgression = "total_progression"
        case cfi
    }

    /// True when this locator says enough to restore anything. The API refuses
    /// the rest, so sending one would be a wasted round trip.
    public var isRestorable: Bool {
        href != nil || totalProgression != nil
    }

    public static func decode(from value: String) -> ReadingLocator? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReadingLocator.self, from: data)
    }

    /// Compact JSON with the null fields omitted, matching what the API stores.
    public func encoded() -> String? {
        var payload: [String: Any] = [:]
        if let href { payload["href"] = href }
        if let progression { payload["progression"] = progression }
        if let totalProgression { payload["total_progression"] = totalProgression }
        if let cfi { payload["cfi"] = cfi }
        guard !payload.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public extension ReadingPosition {
    /// The locator this position carries, when it is one.
    var locator: ReadingLocator? {
        guard positionType == "locator" else { return nil }
        return ReadingLocator.decode(from: positionValue)
    }
}
