import BeryndaCore
import Combine
import Foundation
import UIKit

/// Keeps the device and the server in step: sends the queued writes, adopts
/// newer positions the server already had, and looks after the offline shelf
/// (revalidation, expiry, re-download of changed files).
@MainActor
final class OfflineSync: ObservableObject {
    @Published private(set) var copies: [OfflineCopy] = []
    /// Downloads in progress, 0…1.
    @Published private(set) var downloads: [UUID: Double] = [:]
    @Published var saveError: String?

    let outbox: MutationOutbox
    let library: OfflineLibrary
    private let sender: (any MutationSending)?
    private let statusChecker: (any OfflineStatusChecking)?
    private let source: any ReaderRepository
    private let localPositions: LocalReadingPositionStore
    private var downloadTasks: [UUID: Task<Void, Never>] = [:]
    private var isSyncing = false

    init(
        outbox: MutationOutbox,
        library: OfflineLibrary,
        sender: (any MutationSending)?,
        statusChecker: (any OfflineStatusChecking)?,
        source: any ReaderRepository,
        localPositions: LocalReadingPositionStore
    ) {
        self.outbox = outbox
        self.library = library
        self.sender = sender
        self.statusChecker = statusChecker
        self.source = source
        self.localPositions = localPositions
    }

    // MARK: Outbox

    /// Queues a write for the signed-in account. Without a known account
    /// there is nobody to send it for, so it is not kept.
    func enqueue(_ mutation: PendingMutation, ownerID: UUID?) async {
        guard let ownerID else { return }
        await outbox.enqueue(mutation, ownerID: ownerID)
    }

    /// Run on connectivity, on returning to the foreground and after sign-in.
    func sync(ownerID: UUID?) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        if let ownerID, let sender {
            let report = await outbox.flush(ownerID: ownerID, sender: sender)
            for superseded in report.superseded where superseded.position.positionType == "page" {
                if let page = Int(superseded.position.positionValue) {
                    await localPositions.save(
                        page: page,
                        totalPages: superseded.position.totalPages,
                        for: superseded.fileID
                    )
                }
            }
        }
        await maintainShelf()
    }

    /// Nothing queued may outlive the account that queued it.
    func forgetQueuedWrites() async {
        await outbox.clear()
    }

    // MARK: Offline shelf

    func refreshCopies() async {
        copies = await library.copies()
    }

    func isSaved(_ fileID: UUID) -> Bool {
        copies.contains { $0.fileID == fileID }
    }

    func save(fileID: UUID) {
        guard downloadTasks[fileID] == nil else { return }
        downloads[fileID] = 0
        saveError = nil
        let library = self.library
        let source = self.source
        downloadTasks[fileID] = Task { @MainActor [weak self] in
            // Pages are fetched one by one through the signed API client, so
            // the save runs in the app; leaving it briefly does not stop it.
            let background = UIApplication.shared.beginBackgroundTask(withName: "offline-save")
            defer { UIApplication.shared.endBackgroundTask(background) }
            do {
                try await library.save(fileID: fileID, from: source) { fraction in
                    Task { @MainActor [weak self] in
                        guard self?.downloads[fileID] != nil else { return }
                        self?.downloads[fileID] = fraction
                    }
                }
            } catch is CancellationError {
            } catch {
                self?.saveError = error.localizedDescription
            }
            await self?.finishDownload(fileID)
        }
    }

    func cancelSave(fileID: UUID) {
        downloadTasks[fileID]?.cancel()
    }

    func remove(fileID: UUID) async {
        downloadTasks[fileID]?.cancel()
        await library.remove(fileID: fileID)
        await refreshCopies()
    }

    func removeAll() async {
        for task in downloadTasks.values { task.cancel() }
        await library.removeAll()
        await refreshCopies()
    }

    private func finishDownload(_ fileID: UUID) async {
        downloadTasks[fileID] = nil
        downloads[fileID] = nil
        await refreshCopies()
    }

    /// Expired copies go; when the server can be asked, copies no longer
    /// allowed go too, and changed ones are fetched again.
    private func maintainShelf() async {
        await library.evictExpired()
        if let statusChecker,
           let result = try? await library.revalidate(using: statusChecker) {
            for fileID in result.stale { save(fileID: fileID) }
        }
        await refreshCopies()
    }
}
