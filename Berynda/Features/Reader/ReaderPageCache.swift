import Foundation

/// A rendered page as it comes off the network, before it becomes reader
/// content. Raw bytes rather than a decoded document so it can cross actor
/// boundaries and be measured against a byte ceiling.
enum ReaderPageContent: Sendable, Equatable {
    case pdf(Data, tracksDocumentPages: Bool)
    case image(Data)

    var byteCount: Int {
        switch self {
        case let .pdf(data, _): data.count
        case let .image(data): data.count
        }
    }
}

/// Bounded, per-reader page cache.
///
/// A page turn used to re-download every page, so paging back one page paid
/// full network cost again. Caching is what makes prefetch worth doing, and
/// the bounds are what keep a 200-page session from growing without limit:
/// eviction is least-recently-used, and both a page count and a byte ceiling
/// apply, because a scan image and a text-only PDF page differ by orders of
/// magnitude in size.
actor ReaderPageCache {
    private struct Entry {
        let content: ReaderPageContent
        let byteCount: Int
    }

    private var storage: [Int: Entry] = [:]
    /// Least-recently-used first.
    private var order: [Int] = []
    private let maximumPages: Int
    private let maximumBytes: Int
    private(set) var byteCount = 0

    init(maximumPages: Int = 8, maximumBytes: Int = 24 * 1_024 * 1_024) {
        self.maximumPages = max(1, maximumPages)
        self.maximumBytes = max(1, maximumBytes)
    }

    var pageCount: Int { storage.count }

    var cachedPages: Set<Int> { Set(storage.keys) }

    func content(for page: Int) -> ReaderPageContent? {
        guard let entry = storage[page] else { return nil }
        touch(page)
        return entry.content
    }

    func store(_ content: ReaderPageContent, for page: Int) {
        // A single page larger than the whole budget would evict everything
        // and still not fit, so it is simply not cached.
        let cost = content.byteCount
        guard cost <= maximumBytes else { return }

        if let existing = storage[page] {
            byteCount -= existing.byteCount
        }
        storage[page] = Entry(content: content, byteCount: cost)
        byteCount += cost
        touch(page)
        evictIfNeeded()
    }

    /// Called when the app is backgrounded or memory is tight: the pages are
    /// all re-fetchable, so they are the first thing to give up.
    func removeAll() {
        storage.removeAll()
        order.removeAll()
        byteCount = 0
    }

    private func touch(_ page: Int) {
        order.removeAll { $0 == page }
        order.append(page)
    }

    private func evictIfNeeded() {
        while storage.count > maximumPages || byteCount > maximumBytes {
            guard let oldest = order.first else { return }
            order.removeFirst()
            if let removed = storage.removeValue(forKey: oldest) {
                byteCount -= removed.byteCount
            }
        }
    }
}
