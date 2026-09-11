import Foundation

/// How many bytes the app keeps on this device, by category.
///
/// The Keychain is deliberately absent: tokens are credentials, not storage a
/// reader should size or sweep. `UserDefaults` preferences (appearance,
/// language, reader sizes) are a few bytes and are not counted either, because
/// "clear local data" must never silently reset how the app looks.
struct LocalStorageUsage: Equatable, Sendable {
    /// `reading-positions-v1.json` — local resume points.
    let readingPositionsBytes: Int64
    /// `recently-viewed-v1.json` — the catalog's offline fallback.
    let recentlyViewedBytes: Int64
    /// Publication and export copies under the reader's temporary directory.
    /// A reader deletes its own copy on close, so anything here outlived a
    /// crash or a kill.
    let readerTemporaryBytes: Int64

    var totalBytes: Int64 {
        readingPositionsBytes + recentlyViewedBytes + readerTemporaryBytes
    }

    static let empty = LocalStorageUsage(
        readingPositionsBytes: 0,
        recentlyViewedBytes: 0,
        readerTemporaryBytes: 0
    )
}

/// Measures and evicts what the app stores on device.
///
/// Sizing walks the file system, so it runs on this actor rather than the main
/// thread. Eviction goes through each store's own `clear` so a store never
/// finds its file gone behind its back, and only the reader's temporary
/// directory is swept — never the whole `tmp/`, which other components share.
actor LocalStorageSummary {
    private let readingPositions: LocalReadingPositionStore
    private let recentlyViewed: RecentlyViewedStore
    private let readerTemporaryDirectory: URL
    private let fileManager: FileManager

    /// - Parameters:
    ///   - readingPositions: The store whose file is sized and cleared.
    ///   - recentlyViewed: The store whose file is sized and cleared.
    ///   - readerTemporaryDirectory: Where `ProtectedTemporaryFile` writes.
    ///     Injectable so tests can point it at a scratch folder; a missing
    ///     directory measures as zero and is not an error.
    init(
        readingPositions: LocalReadingPositionStore,
        recentlyViewed: RecentlyViewedStore,
        readerTemporaryDirectory: URL = ProtectedTemporaryFile.directory,
        fileManager: FileManager = .default
    ) {
        self.readingPositions = readingPositions
        self.recentlyViewed = recentlyViewed
        self.readerTemporaryDirectory = readerTemporaryDirectory
        self.fileManager = fileManager
    }

    func measure() -> LocalStorageUsage {
        LocalStorageUsage(
            readingPositionsBytes: size(ofFile: readingPositions.fileURL),
            recentlyViewedBytes: size(ofFile: recentlyViewed.fileURL),
            readerTemporaryBytes: size(ofDirectory: readerTemporaryDirectory)
        )
    }

    /// Removes both JSON stores and every leftover reader file, then measures
    /// again so the caller shows what is actually left rather than assuming
    /// zero.
    func clearCaches() async -> LocalStorageUsage {
        await readingPositions.clearAll()
        await recentlyViewed.clear()
        removeContents(of: readerTemporaryDirectory)
        return measure()
    }

    private func size(ofFile url: URL?) -> Int64 {
        guard let url else { return 0 }
        // A fresh URL on every call: `resourceValues` caches on the URL object,
        // and each store hands out the same `fileURL` for its lifetime, so a
        // cached size would outlive the file being cleared.
        return regularFileSize(of: URL(fileURLWithPath: url.path))
    }

    /// Sum over regular files only. A missing directory enumerates nothing,
    /// which is zero rather than an error.
    private func size(ofDirectory directory: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else { return 0 }
        var total: Int64 = 0
        // Enumerated URLs are new objects, so their prefetched values are current.
        for case let url as URL in enumerator {
            total += regularFileSize(of: url)
        }
        return total
    }

    private func regularFileSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true
        else { return 0 }
        return Int64(values.fileSize ?? 0)
    }

    private func removeContents(of directory: URL) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return }
        for entry in entries {
            try? fileManager.removeItem(at: entry)
        }
    }
}
