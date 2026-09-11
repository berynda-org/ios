import BeryndaCore
import Foundation

/// A work the reader opened, kept so the catalog has something to show when
/// the network is gone.
///
/// Deliberately not a cached `WorkSummary`: only what a row needs to render
/// and to route on tap, so the file cannot become a stale mirror of the
/// catalog that quietly disagrees with the server about rights or counts.
struct RecentlyViewedWork: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let slug: String
    let title: String
    let authorNames: [String]
    let coverTone: String?
    let coverVariant: String?
    let coverGlyph: String?
    let viewedAt: Date

    var coverDesign: CoverDesign {
        CoverDesign.resolve(
            workID: id,
            title: title,
            persistedTone: coverTone,
            persistedVariant: coverVariant,
            persistedGlyph: coverGlyph
        )
    }
}

/// Bounded, on-device history of opened works.
///
/// This is reading history, so it follows the same privacy rule the reading
/// position does: when the reader has turned history off, nothing is written
/// and anything already stored is dropped.
actor RecentlyViewedStore {
    /// Where the history lives, so `LocalStorageSummary` can size the file
    /// without duplicating the name. `nil` when no support directory exists.
    nonisolated let fileURL: URL?
    private let fileManager: FileManager
    private let limit: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil, fileManager: FileManager = .default, limit: Int = 20) {
        self.fileManager = fileManager
        self.limit = max(1, limit)
        let base = directory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("Berynda", isDirectory: true)
        if let base {
            try? fileManager.createDirectory(
                at: base,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var protectedBase = base
            try? protectedBase.setResourceValues(values)
            fileURL = base.appendingPathComponent("recently-viewed-v1.json")
        } else {
            fileURL = nil
        }
    }

    /// Most recently viewed first.
    func recent() -> [RecentlyViewedWork] {
        records().sorted { $0.viewedAt > $1.viewedAt }
    }

    func record(_ work: WorkSummary, at date: Date = Date()) {
        let entry = RecentlyViewedWork(
            id: work.id,
            slug: work.slug,
            title: work.title,
            authorNames: work.authors.map { $0.displayName },
            coverTone: work.coverTone,
            coverVariant: work.coverVariant,
            coverGlyph: work.coverGlyph,
            viewedAt: date
        )
        // Re-opening a work moves it to the front rather than duplicating it.
        var updated = records().filter { $0.id != entry.id }
        updated.append(entry)
        updated.sort { $0.viewedAt > $1.viewedAt }
        write(Array(updated.prefix(limit)))
    }

    func clear() {
        guard let fileURL else { return }
        try? fileManager.removeItem(at: fileURL)
    }

    private func records() -> [RecentlyViewedWork] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([RecentlyViewedWork].self, from: data)) ?? []
    }

    private func write(_ works: [RecentlyViewedWork]) {
        guard let fileURL, let data = try? encoder.encode(works) else { return }
        try? data.write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}
