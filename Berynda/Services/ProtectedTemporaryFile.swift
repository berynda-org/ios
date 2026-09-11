import Foundation

/// Writes document bytes to temporary storage with complete file protection
/// and no backup, and deletes them when the reader is done.
///
/// Publications and exported documents both need identical handling, so this
/// is the one implementation: a second copy would be the one that quietly
/// drops a protection flag.
enum ProtectedTemporaryFile {
    /// The one directory reader copies are written to. `LocalStorageSummary`
    /// sweeps exactly this directory, so it is named here and nowhere else.
    static var directory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("org.berynda.ios", isDirectory: true)
            .appendingPathComponent("reader", isDirectory: true)
    }

    static func write(
        _ data: Data,
        fileID: UUID,
        pathExtension: String
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            let directory = ProtectedTemporaryFile.directory
            try manager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )

            var fileURL = directory.appendingPathComponent(
                "\(fileID.uuidString.lowercased())-\(UUID().uuidString.lowercased())"
                    + ".\(pathExtension)",
                isDirectory: false
            )
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try fileURL.setResourceValues(values)
            return fileURL
        }.value
    }

    static func remove(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
