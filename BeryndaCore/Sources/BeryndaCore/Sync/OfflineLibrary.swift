import Foundation

/// One edition file kept on the device for offline reading.
public struct OfflineCopy: Codable, Sendable, Identifiable, Equatable {
    public let fileID: UUID
    public let workID: UUID
    public let title: String
    public let authors: [String]
    public let kind: OfflinePolicy.Kind
    public let totalPages: Int?
    public let maxAgeDays: Int
    public let savedAt: Date
    public var lastOpenedAt: Date
    public var lastValidatedAt: Date
    /// The file's `updated_at` when last checked; a change means the copy
    /// should be fetched again.
    public var serverUpdatedAt: String?
    public var byteCount: Int64
    public var needsRefresh: Bool

    public var id: UUID { fileID }

    /// Kept until this long after it was last opened or last confirmed by
    /// the server, whichever is later.
    public func expiresAt(calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        let anchor = max(lastOpenedAt, lastValidatedAt)
        return calendar.date(byAdding: .day, value: maxAgeDays, to: anchor) ?? anchor
    }
}

/// `POST files/offline-status/` for one file.
public struct OfflineFileStatus: Decodable, Sendable, Equatable {
    public let id: String
    public let canSaveOffline: Bool
    public let canRead: Bool
    public let updatedAt: String?

    public init(id: String, canSaveOffline: Bool, canRead: Bool, updatedAt: String?) {
        self.id = id
        self.canSaveOffline = canSaveOffline
        self.canRead = canRead
        self.updatedAt = updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        canSaveOffline = (try? container.decode(Bool.self, forKey: .canSaveOffline)) ?? false
        canRead = (try? container.decode(Bool.self, forKey: .canRead)) ?? false
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case canSaveOffline = "can_save_offline"
        case canRead = "can_read"
        case updatedAt = "updated_at"
    }
}

public protocol OfflineStatusChecking: Sendable {
    func offlineStatus(fileIDs: [UUID]) async throws -> [OfflineFileStatus]
}

public struct LiveOfflineStatusChecker: OfflineStatusChecking {
    private let client: BeryndaAPIClient

    public init(client: BeryndaAPIClient) {
        self.client = client
    }

    /// Asks in batches of 200, the server's limit.
    public func offlineStatus(fileIDs: [UUID]) async throws -> [OfflineFileStatus] {
        var statuses: [OfflineFileStatus] = []
        var start = 0
        while start < fileIDs.count {
            let batch = Array(fileIDs[start..<min(start + 200, fileIDs.count)])
            let response: OfflineStatusResponse = try await client.request(
                .offlineStatus,
                method: .post,
                body: OfflineStatusRequest(fileIDs: batch.map { $0.uuidString.lowercased() })
            )
            statuses.append(contentsOf: response.files)
            start += 200
        }
        return statuses
    }
}

private struct OfflineStatusRequest: Encodable, Sendable {
    let fileIDs: [String]
    enum CodingKeys: String, CodingKey { case fileIDs = "file_ids" }
}

private struct OfflineStatusResponse: Decodable, Sendable {
    let files: [OfflineFileStatus]
}

public enum OfflineSaveError: Error, Equatable, Sendable {
    case notAllowed
    case notReady
    case storageFull
    case inProgress
}

extension OfflineSaveError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAllowed: "Це видання не можна зберегти для читання офлайн."
        case .notReady: "Сторінки ще готуються. Спробуйте зберегти трохи згодом."
        case .storageFull: "Для збереження бракує місця, відведеного для офлайн-читання. Видаліть щось у «Сховищі»."
        case .inProgress: "Це видання вже зберігається."
        }
    }
}

public struct OfflineRevalidation: Sendable, Equatable {
    public var removed: [UUID] = []
    public var stale: [UUID] = []

    public init() {}
}

/// The offline shelf: what the reader streams, kept in protected,
/// non-exportable, non-backed-up storage under the app's own directory.
///
/// Each copy is a folder: `manifest.json`, `info.json` (the reader-info it was
/// saved with), and either `content.json`/`content.epub` or `pages/<n>`.
public actor OfflineLibrary {
    /// Page images are kept at this width: sharp on a phone, a fraction of
    /// the reader's on-screen request.
    public static let pageWidth = 1_200
    public static let defaultCapacity: Int64 = 1_536 * 1_024 * 1_024

    private let directory: URL
    private let capacity: Int64
    private let now: @Sendable () -> Date
    private var manifests: [UUID: OfflineCopy] = [:]
    private var didLoad = false
    private var saving: Set<UUID> = []

    public init(
        directory: URL,
        capacity: Int64 = OfflineLibrary.defaultCapacity,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.capacity = capacity
        self.now = now
    }

    public static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("Berynda", isDirectory: true)
            .appendingPathComponent("Offline", isDirectory: true)
    }

    // MARK: Shelf

    public func copies() -> [OfflineCopy] {
        loadIfNeeded()
        return manifests.values.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    public func copy(fileID: UUID) -> OfflineCopy? {
        loadIfNeeded()
        return manifests[fileID]
    }

    public func totalBytes() -> Int64 {
        loadIfNeeded()
        return manifests.values.reduce(0) { $0 + $1.byteCount }
    }

    public func isSaving(fileID: UUID) -> Bool {
        saving.contains(fileID)
    }

    /// Fetches everything the policy allows into a staging folder, then puts
    /// it in place in one move, so a failed or cancelled save leaves nothing
    /// half-written behind.
    @discardableResult
    public func save(
        fileID: UUID,
        from source: any ReaderRepository,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> OfflineCopy {
        loadIfNeeded()
        guard !saving.contains(fileID) else { throw OfflineSaveError.inProgress }
        saving.insert(fileID)
        defer { saving.remove(fileID) }

        let info = try await source.info(fileID: fileID)
        guard info.rights.canRead, info.rights.canSaveOffline else { throw OfflineSaveError.notAllowed }
        guard let policy = info.offline else { throw OfflineSaveError.notReady }

        let staging = directory.appendingPathComponent(".\(fileID.uuidString.lowercased()).partial", isDirectory: true)
        try? FileManager.default.removeItem(at: staging)
        ProtectedStorage.prepareDirectory(staging)
        var keepStaging = false
        defer { if !keepStaging { try? FileManager.default.removeItem(at: staging) } }

        let budget = capacity - (totalBytes() - (manifests[fileID]?.byteCount ?? 0))
        var bytes: Int64 = 0
        func store(_ data: Data, as name: String) throws {
            bytes += Int64(data.count)
            guard bytes <= budget else { throw OfflineSaveError.storageFull }
            ProtectedStorage.write(data, to: staging.appendingPathComponent(name, isDirectory: false))
        }

        var totalPages: Int?
        switch policy.kind {
        case .content:
            switch info.renderingMode {
            case .text, .markdown:
                let text = try await source.text(fileID: fileID)
                try store(try JSONEncoder().encode(text), as: "content.json")
            case .epub:
                try store(try await source.epubDocument(fileID: fileID), as: "content.epub")
            case .pdf, .djvu:
                throw OfflineSaveError.notAllowed
            }
            progress(1)
        case .pages:
            guard let pageCount = policy.totalPages ?? info.totalPages, pageCount > 0 else {
                throw OfflineSaveError.notReady
            }
            ProtectedStorage.prepareDirectory(staging.appendingPathComponent("pages", isDirectory: true))
            for page in 1...pageCount {
                try Task.checkCancellation()
                let image = try await source.pageImage(fileID: fileID, page: page, width: Self.pageWidth)
                try store(image, as: "pages/\(page)")
                progress(Double(page) / Double(pageCount))
            }
            totalPages = pageCount
        case .unsupported:
            throw OfflineSaveError.notReady
        }
        try Task.checkCancellation()

        let infoData = try JSONEncoder().encode(info)
        try store(infoData, as: "info.json")
        let moment = now()
        let copy = OfflineCopy(
            fileID: fileID,
            workID: info.workID,
            title: info.book.title,
            authors: info.book.authors,
            kind: policy.kind,
            totalPages: totalPages,
            maxAgeDays: policy.maxAgeDays,
            savedAt: moment,
            lastOpenedAt: moment,
            lastValidatedAt: moment,
            serverUpdatedAt: nil,
            byteCount: bytes,
            needsRefresh: false
        )
        ProtectedStorage.write(try JSONEncoder().encode(copy), to: staging.appendingPathComponent("manifest.json"))

        let destination = folder(for: fileID)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: staging, to: destination)
        keepStaging = true
        ProtectedStorage.excludeFromBackup(destination)
        manifests[fileID] = copy
        return copy
    }

    public func remove(fileID: UUID) {
        loadIfNeeded()
        try? FileManager.default.removeItem(at: folder(for: fileID))
        manifests[fileID] = nil
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        manifests.removeAll()
    }

    // MARK: Reading

    /// The reader-info the copy was saved with, adjusted so a paged copy is
    /// read from its stored page images.
    public func readerInfo(fileID: UUID) -> ReaderInfo? {
        loadIfNeeded()
        guard let copy = manifests[fileID],
              let data = try? Data(contentsOf: folder(for: fileID).appendingPathComponent("info.json"))
        else { return nil }
        guard copy.kind == .pages else { return try? JSONDecoder().decode(ReaderInfo.self, from: data) }
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        object["page_delivery"] = PageDelivery.serverPages.rawValue
        if let pages = copy.totalPages { object["total_pages"] = pages }
        guard let adjusted = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(ReaderInfo.self, from: adjusted)
    }

    public func text(fileID: UUID) -> TextReaderContent? {
        guard manifests[fileID]?.kind == .content,
              let data = try? Data(contentsOf: folder(for: fileID).appendingPathComponent("content.json"))
        else { return nil }
        return try? JSONDecoder().decode(TextReaderContent.self, from: data)
    }

    public func epubDocument(fileID: UUID) -> Data? {
        guard manifests[fileID]?.kind == .content else { return nil }
        return try? Data(contentsOf: folder(for: fileID).appendingPathComponent("content.epub"))
    }

    public func pageImage(fileID: UUID, page: Int) -> Data? {
        guard manifests[fileID]?.kind == .pages else { return nil }
        return try? Data(contentsOf: folder(for: fileID)
            .appendingPathComponent("pages", isDirectory: true)
            .appendingPathComponent(String(page)))
    }

    /// Opening a copy restarts its keep-alive window.
    public func noteOpened(fileID: UUID) {
        loadIfNeeded()
        guard var copy = manifests[fileID] else { return }
        copy.lastOpenedAt = now()
        update(copy)
    }

    // MARK: Upkeep

    /// Removes copies neither opened nor confirmed within their `max_age_days`.
    @discardableResult
    public func evictExpired() -> [UUID] {
        loadIfNeeded()
        let moment = now()
        let expired = manifests.values.filter { $0.expiresAt() < moment }.map(\.fileID)
        for fileID in expired { remove(fileID: fileID) }
        return expired
    }

    /// Asks the server whether each copy may still be kept: copies no longer
    /// allowed are deleted, confirmed ones restart their window, and ones whose
    /// file changed are marked for a fresh download.
    public func revalidate(using checker: any OfflineStatusChecking) async throws -> OfflineRevalidation {
        loadIfNeeded()
        var result = OfflineRevalidation()
        let ids = Array(manifests.keys)
        guard !ids.isEmpty else { return result }
        let statuses = try await checker.offlineStatus(fileIDs: ids)
        let moment = now()
        for status in statuses {
            guard let fileID = UUID(uuidString: status.id), var copy = manifests[fileID] else { continue }
            guard status.canRead, status.canSaveOffline else {
                remove(fileID: fileID)
                result.removed.append(fileID)
                continue
            }
            copy.lastValidatedAt = moment
            if let updated = status.updatedAt {
                if let known = copy.serverUpdatedAt, known != updated {
                    copy.needsRefresh = true
                }
                copy.serverUpdatedAt = updated
            }
            if copy.needsRefresh { result.stale.append(fileID) }
            update(copy)
        }
        return result
    }

    // MARK: Storage

    private func folder(for fileID: UUID) -> URL {
        directory.appendingPathComponent(fileID.uuidString.lowercased(), isDirectory: true)
    }

    private func update(_ copy: OfflineCopy) {
        manifests[copy.fileID] = copy
        guard let data = try? JSONEncoder().encode(copy) else { return }
        ProtectedStorage.write(data, to: folder(for: copy.fileID).appendingPathComponent("manifest.json"))
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for entry in entries {
            if entry.lastPathComponent.hasPrefix(".") {
                // A save interrupted by the app being killed.
                try? fileManager.removeItem(at: entry)
                continue
            }
            guard let data = try? Data(contentsOf: entry.appendingPathComponent("manifest.json")),
                  let copy = try? JSONDecoder().decode(OfflineCopy.self, from: data)
            else {
                try? fileManager.removeItem(at: entry)
                continue
            }
            manifests[copy.fileID] = copy
        }
    }
}

/// Reads from the offline shelf where it can: saved content and pages always
/// (no need to download them twice), and the saved reader-info when the
/// network cannot be reached.
public struct OfflineAwareReaderRepository: ReaderRepository {
    private let live: any ReaderRepository
    private let library: OfflineLibrary

    public init(live: any ReaderRepository, library: OfflineLibrary) {
        self.live = live
        self.library = library
    }

    public func info(fileID: UUID) async throws -> ReaderInfo {
        do {
            // Online, the live record wins: it carries the latest position
            // and rights. Saved pages and content are still used below.
            let info = try await live.info(fileID: fileID)
            await library.noteOpened(fileID: fileID)
            return info
        } catch {
            guard MutationOutbox.isTransient(error), let stored = await library.readerInfo(fileID: fileID) else {
                throw error
            }
            await library.noteOpened(fileID: fileID)
            return stored
        }
    }

    public func text(fileID: UUID) async throws -> TextReaderContent {
        if let stored = await library.text(fileID: fileID) { return stored }
        return try await live.text(fileID: fileID)
    }

    public func epubDocument(fileID: UUID) async throws -> Data {
        if let stored = await library.epubDocument(fileID: fileID) { return stored }
        return try await live.epubDocument(fileID: fileID)
    }

    public func fullDocument(fileID: UUID) async throws -> Data {
        try await live.fullDocument(fileID: fileID)
    }

    public func pagePDF(fileID: UUID, page: Int) async throws -> Data {
        try await live.pagePDF(fileID: fileID, page: page)
    }

    public func pageImage(fileID: UUID, page: Int, width: Int) async throws -> Data {
        if let stored = await library.pageImage(fileID: fileID, page: page) { return stored }
        return try await live.pageImage(fileID: fileID, page: page, width: width)
    }

    public func savePosition(
        fileID: UUID,
        positionType: String,
        positionValue: String,
        progressPercent: Int?,
        totalPages: Int?
    ) async throws -> Bool {
        try await live.savePosition(
            fileID: fileID,
            positionType: positionType,
            positionValue: positionValue,
            progressPercent: progressPercent,
            totalPages: totalPages
        )
    }
}
