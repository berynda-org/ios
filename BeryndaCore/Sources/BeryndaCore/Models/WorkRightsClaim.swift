import Foundation

/// Rights labels that can be supported by the catalog response. Imported file
/// regimes alone do not establish that a work is in the public domain.
public enum WorkRightsClaim: String, Sendable {
    case publicDomain = "public_domain"
    case openLicense = "open_license"
    case byPermission = "by_permission"
    case selfPublished = "self_published"

    public init?(rightsSummary: String?, pdStatus: String?) {
        guard let rightsSummary, let claim = Self(rawValue: rightsSummary) else { return nil }
        guard claim != .publicDomain || pdStatus == "confirmed" else { return nil }
        self = claim
    }
}

public extension WorkSummary {
    /// Shared by catalog rows and work details, matching the website's rule.
    var rightsClaim: WorkRightsClaim? {
        WorkRightsClaim(rightsSummary: rightsSummary, pdStatus: pdStatus)
    }
}
