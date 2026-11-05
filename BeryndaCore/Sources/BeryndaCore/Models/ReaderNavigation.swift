import Foundation

public struct ReaderContentsItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let page: Int
    public let depth: Int

    public init(id: UUID, title: String, page: Int, depth: Int) {
        self.id = id
        self.title = title
        self.page = page
        self.depth = depth
    }
}

public enum ReaderNavigation {
    /// Produces only destinations that belong to the current work and resolve to a valid page.
    public static func contents(
        from entries: [ReaderTOCEntry],
        workID: UUID,
        totalPages: Int?
    ) -> [ReaderContentsItem] {
        var result: [ReaderContentsItem] = []
        var pending = entries.reversed().map { ($0, 0) }

        while let (entry, depth) = pending.popLast() {
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty,
               entry.workID == nil || entry.workID == workID,
               let page = entry.pageNumber,
               page > 0,
               totalPages.map({ page <= $0 }) ?? true {
                result.append(
                    ReaderContentsItem(
                        id: entry.id,
                        title: title,
                        page: page,
                        depth: min(depth, 8)
                    )
                )
            }

            for child in entry.children.reversed() {
                pending.append((child, depth + 1))
            }
        }

        return result
    }

    public static func pageLabel(for page: Int, in labels: [ReaderPageLabel]) -> String? {
        guard page > 0,
              let label = labels.first(where: { $0.page == page })?.label
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty
        else { return nil }
        return label
    }
}
