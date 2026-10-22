import Foundation

/// The `Idempotency-Key` header: one opaque key per intended mutation, so a
/// retry after a lost response replays the first result instead of writing
/// twice.
public enum IdempotencyKey {
    public static let headerName = "Idempotency-Key"

    public static func make() -> String {
        UUID().uuidString.lowercased()
    }

    /// 1–128 printable ASCII characters, no spaces — the server's rule.
    public static func isValid(_ key: String) -> Bool {
        guard (1...128).contains(key.utf8.count) else { return false }
        return key.utf8.allSatisfy { (0x21...0x7E).contains($0) }
    }

    static func headers(_ key: String) -> [String: String] {
        [headerName: key]
    }
}

/// The body of `POST lists/quick-add/`, kept so a queued quick add can be
/// sent later exactly as it was asked for.
public struct QuickAddRequest: Codable, Sendable, Equatable {
    public let workID: UUID?
    public let fileID: UUID?
    public let positionType: String?
    public let positionValue: String?
    public let pageNumber: Int?

    public init(workID: UUID?, fileID: UUID?, positionType: String?, positionValue: String?, pageNumber: Int?) {
        self.workID = workID
        self.fileID = fileID
        self.positionType = positionType
        self.positionValue = positionValue
        self.pageNumber = pageNumber
    }
}

/// A write the device owes the server.
public enum PendingMutation: Codable, Sendable, Equatable {
    /// `clientUpdatedAt` is when the reader was really there, so a newer
    /// position from another device is not overwritten by a late flush.
    case readingPosition(fileID: UUID, update: ReadingPositionUpdate, clientUpdatedAt: Date)
    case createList(title: String)
    case renameList(id: UUID, title: String)
    case deleteList(id: UUID)
    case addWork(listID: UUID, workID: UUID)
    case removeItem(listID: UUID, itemID: UUID)
    case quickAdd(QuickAddRequest)

    var positionFileID: UUID? {
        if case let .readingPosition(fileID, _, _) = self { return fileID }
        return nil
    }
}

public struct OutboxEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    /// The account the write belongs to. It is never sent for anyone else.
    public let ownerID: UUID
    /// Generated once, when queued, and reused on every attempt.
    public let idempotencyKey: String
    public let createdAt: Date
    public var attempts: Int
    public let mutation: PendingMutation
}

/// A queued position the server declined because it already had a newer
/// one, which the device should adopt.
public struct SupersededPosition: Sendable, Equatable {
    public let fileID: UUID
    public let position: ReadingPosition

    public init(fileID: UUID, position: ReadingPosition) {
        self.fileID = fileID
        self.position = position
    }
}

public enum OutboxDelivery: Sendable, Equatable {
    case delivered
    case superseded(SupersededPosition)
}

public protocol MutationSending: Sendable {
    func deliver(_ mutation: PendingMutation, idempotencyKey: String) async throws -> OutboxDelivery
}

public struct OutboxFlushReport: Sendable, Equatable {
    public var delivered = 0
    public var dropped = 0
    public var remaining = 0
    public var superseded: [SupersededPosition] = []

    public init() {}
}

/// Writes made while offline (or whose request failed in transit), kept in a
/// protected, non-backed-up file until they reach the server.
///
/// Positions are coalesced per file: only the latest matters. Everything is
/// sent in the order it was made, and only for the account that made it.
public actor MutationOutbox {
    /// Attempts after which an entry that keeps failing is given up on.
    static let maximumAttempts = 50

    private let fileURL: URL?
    private var queue: [OutboxEntry] = []
    private var didLoad = false
    private var isFlushing = false

    /// `fileURL` nil keeps the queue in memory only (tests, UI tests).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return support
            .appendingPathComponent("Berynda", isDirectory: true)
            .appendingPathComponent("outbox.json", isDirectory: false)
    }

    public func entries() -> [OutboxEntry] {
        loadIfNeeded()
        return queue
    }

    public func enqueue(
        _ mutation: PendingMutation,
        ownerID: UUID,
        idempotencyKey: String = IdempotencyKey.make(),
        now: Date = Date()
    ) {
        loadIfNeeded()
        if let fileID = mutation.positionFileID {
            queue.removeAll { $0.ownerID == ownerID && $0.mutation.positionFileID == fileID }
        }
        queue.append(OutboxEntry(
            id: UUID(),
            ownerID: ownerID,
            idempotencyKey: IdempotencyKey.isValid(idempotencyKey) ? idempotencyKey : IdempotencyKey.make(),
            createdAt: now,
            attempts: 0,
            mutation: mutation
        ))
        persist()
    }

    /// Forgets every queued write: on sign-out, account deletion or a switch
    /// to another account.
    public func clear() {
        loadIfNeeded()
        queue.removeAll()
        persist()
    }

    /// Sends what `ownerID` owes, oldest first. Writes queued by another
    /// account are dropped, never sent. A transient failure stops the flush
    /// and keeps the rest for next time; a refusal drops that one entry.
    public func flush(ownerID: UUID, sender: any MutationSending) async -> OutboxFlushReport {
        loadIfNeeded()
        var report = OutboxFlushReport()
        guard !isFlushing else {
            report.remaining = queue.count
            return report
        }
        isFlushing = true
        defer { isFlushing = false }

        let foreign = queue.filter { $0.ownerID != ownerID }.count
        if foreign > 0 {
            queue.removeAll { $0.ownerID != ownerID }
            report.dropped += foreign
            persist()
        }

        while let entry = queue.first {
            do {
                let delivery = try await sender.deliver(entry.mutation, idempotencyKey: entry.idempotencyKey)
                remove(entry.id)
                report.delivered += 1
                if case let .superseded(position) = delivery {
                    report.superseded.append(position)
                }
            } catch {
                if Self.isTransient(error) {
                    bumpAttempts(entry.id)
                    break
                }
                remove(entry.id)
                report.dropped += 1
            }
        }
        report.remaining = queue.count
        return report
    }

    /// A failure worth trying again later: no connection, a busy or broken
    /// server, or a session that needs the reader to sign in again.
    public static func isTransient(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let apiError = error as? APIError {
            switch apiError {
            case .transport, .server, .rateLimited, .unauthorized: return true
            default: return false
            }
        }
        if let sessionError = error as? SessionError {
            return sessionError == .unavailable || sessionError == .expired || sessionError == .invalidToken
        }
        return false
    }

    private func remove(_ id: UUID) {
        queue.removeAll { $0.id == id }
        persist()
    }

    private func bumpAttempts(_ id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].attempts += 1
        if queue[index].attempts >= Self.maximumAttempts {
            queue.remove(at: index)
        }
        persist()
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        // An unreadable queue is discarded rather than retried forever.
        queue = (try? JSONDecoder().decode([OutboxEntry].self, from: data)) ?? []
    }

    private func persist() {
        guard let fileURL else { return }
        if queue.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        guard let data = try? JSONEncoder().encode(queue) else { return }
        ProtectedStorage.write(data, to: fileURL)
    }
}

/// Files that hold the reader's data: written atomically, protected while
/// the device is locked where the platform supports it, and kept out of
/// backups.
enum ProtectedStorage {
    static func write(_ data: Data, to url: URL) {
        let directory = url.deletingLastPathComponent()
        prepareDirectory(directory)
        #if os(iOS)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: url, options: [.atomic])
        #endif
        excludeFromBackup(url)
    }

    static func prepareDirectory(_ directory: URL) {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        excludeFromBackup(directory)
    }

    static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = url
        try? target.setResourceValues(values)
    }
}
