import Foundation

struct LocalReadingPosition: Codable, Sendable, Equatable {
    let page: Int
    let totalPages: Int?
    let updatedAt: Date
}

actor LocalReadingPositionStore {
    /// Where the positions live, so `LocalStorageSummary` can size the file
    /// without duplicating the name. `nil` when no support directory exists.
    nonisolated let fileURL: URL?
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
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
            fileURL = base.appendingPathComponent("reading-positions-v1.json")
        } else {
            fileURL = nil
        }
    }

    func position(for fileID: UUID) -> LocalReadingPosition? {
        records()[fileID.uuidString.lowercased()]
    }

    func save(page: Int, totalPages: Int?, for fileID: UUID) {
        var values = records()
        values[fileID.uuidString.lowercased()] = LocalReadingPosition(
            page: max(page, 1),
            totalPages: totalPages,
            updatedAt: Date()
        )
        guard let fileURL, let data = try? encoder.encode(values) else { return }
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
        } catch {
            // Resume is an optional convenience. Never weaken file protection
            // or interrupt reading when protected local storage is unavailable.
        }
    }

    func clearAll() {
        guard let fileURL else { return }
        try? fileManager.removeItem(at: fileURL)
    }

    private func records() -> [String: LocalReadingPosition] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let value = try? decoder.decode([String: LocalReadingPosition].self, from: data)
        else { return [:] }
        return value
    }
}
