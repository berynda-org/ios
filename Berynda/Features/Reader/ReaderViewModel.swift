import BeryndaCore
import Combine
import Foundation
import UIKit

@MainActor
final class EPUBPayload {
    var data: Data?

    init(data: Data) {
        self.data = data
    }
}

@MainActor
final class ReaderViewModel: ObservableObject {
    enum Content {
        case text(String, isMarkdown: Bool)
        case pdf(Data, tracksDocumentPages: Bool)
        case image(Data)
        case epub(EPUBPayload)

        init(_ page: ReaderPageContent) {
            switch page {
            case let .pdf(data, tracksDocumentPages):
                self = .pdf(data, tracksDocumentPages: tracksDocumentPages)
            case let .image(data):
                self = .image(data)
            }
        }
    }

    enum Phase {
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var info: ReaderInfo?
    @Published private(set) var content: Content?
    @Published private(set) var pageIsLoading = false
    @Published var currentPage = 1
    /// The page facing `currentPage` in spread mode; `nil` in single-page mode
    /// or when the spread would run past the end of the document.
    @Published private(set) var facingContent: Content?
    private(set) var isSpreadEnabled = false

    let fileID: UUID
    private let initialPage: Int?
    private let initialCharOffset: Int?
    private let repository: any ReaderRepository
    private let session: SessionController
    private let account: AccountViewModel
    private let localPositions: LocalReadingPositionStore
    /// Where a position that could not be sent waits for the network.
    private let offline: OfflineSync?
    private var pageTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var prefetchTasks: [Int: Task<Void, Never>] = [:]
    private let pageCache = ReaderPageCache()
    /// Protected temporary copy backing the export affordance, deleted when
    /// the reader closes.
    @Published private(set) var exportableDocument: URL?
    private var exportTask: Task<Void, Never>?
    /// Whole text body plus its page boundaries, kept so a page turn is a
    /// substring rather than another walk over the book.
    private var fullText = ""
    private var textPageRanges: [Range<String.Index>] = []
    /// Text books open a page at a time, like the web reader; the
    /// continuous scroll stays one tap away.
    @Published private(set) var isTextPaged = true
    /// Set once a text body is loaded, of either kind.
    private(set) var hasTextBody = false
    /// Length of the text body in UTF-16 code units.
    private var textLength = 0
    /// The reader's place in a text book without server pages: a UTF-16
    /// offset into the body, the unit the web reader's `char` positions use.
    /// It is the anchor every re-pagination keeps on screen, so a rotation
    /// or a text-size change does not lose the place.
    private(set) var textOffset = 0
    /// Pages of a text book laid out for the current screen; `nil` until the
    /// view has paginated it.
    @Published private(set) var textLayout: TextPageMap?
    /// Set when the server answers a position save with `recorded: false`,
    /// i.e. it declined to record because the reader's history policy is off.
    private var serverDeclinedToRecord = false
    /// Latest position reported by the publication renderer, if any.
    private var publicationLocator: ReadingLocator?

    init(
        fileID: UUID,
        initialPage: Int? = nil,
        initialCharOffset: Int? = nil,
        repository: any ReaderRepository,
        session: SessionController,
        account: AccountViewModel,
        localPositions: LocalReadingPositionStore,
        offline: OfflineSync? = nil
    ) {
        self.fileID = fileID
        self.initialPage = initialPage
        self.initialCharOffset = initialCharOffset
        self.repository = repository
        self.session = session
        self.account = account
        self.localPositions = localPositions
        self.offline = offline
    }

    deinit {
        pageTask?.cancel()
        saveTask?.cancel()
        exportTask?.cancel()
        for task in prefetchTasks.values { task.cancel() }
    }

    func load() async {
        phase = .loading
        do {
            let readerInfo = try await repository.info(fileID: fileID)
            guard readerInfo.rights.canRead else {
                throw ReaderFailure.restricted(
                    readerInfo.rights.restrictionReason ?? L("Це видання зараз недоступне для читання.")
                )
            }
            info = readerInfo
            let local = await localPositions.position(for: fileID)
            currentPage = restoredPage(from: readerInfo, local: local)
            try await loadContent(for: readerInfo, local: local)
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func selectPage(_ page: Int) {
        guard let info else { return }
        if usesLayoutPaging {
            guard let layout = textLayout else { return }
            let bounded = min(max(page, 1), layout.pageCount)
            guard bounded != currentPage else { return }
            currentPage = bounded
            textOffset = layout.startOffset(ofPage: bounded)
            schedulePositionSave()
            return
        }
        if isTextPaged, supportsTextPaging {
            let bounded = min(max(page, 1), textPageCount)
            guard bounded != currentPage else { return }
            currentPage = bounded
            refreshVisibleText()
            schedulePositionSave()
            return
        }
        let upperBound = max(info.totalPages ?? page, 1)
        let bounded = min(max(page, 1), upperBound)
        guard bounded != currentPage else { return }
        currentPage = bounded
        schedulePositionSave()

        guard info.isPagedDocument, info.resource != .fullPDF else { return }
        pageTask?.cancel()
        // `bounded`, not `page`: a request past the last page used to leave
        // `pageIsLoading` true forever, because the completion guard compares
        // against the clamped `currentPage` and never matched.
        pageTask = Task { [weak self] in
            await self?.reloadPage(bounded)
        }
    }

    /// Two pages side by side only where the app itself paginates. A full PDF
    /// is laid out by PDFKit, and text and publications reflow, so neither has
    /// a facing page to show.
    var supportsSpread: Bool {
        guard let info else { return false }
        return info.resource == .pagePDF || info.resource == .pageImage
    }

    /// Pages advance two at a time once a spread is on screen, so the reader
    /// does not see the same page again as the left half of the next spread.
    var pageStep: Int { facingContent == nil ? 1 : 2 }

    /// Called by the view when the size class or orientation changes.
    func setSpreadEnabled(_ enabled: Bool) async {
        guard enabled != isSpreadEnabled else { return }
        isSpreadEnabled = enabled
        guard let info else { return }
        if enabled {
            await loadFacingPage(for: currentPage, info: info)
        } else {
            facingContent = nil
        }
    }

    private func loadFacingPage(for page: Int, info: ReaderInfo) async {
        guard isSpreadEnabled, supportsSpread else {
            facingContent = nil
            return
        }
        let facing = page + 1
        if let total = info.totalPages, facing > total {
            facingContent = nil
            return
        }
        if let cached = await pageCache.content(for: facing) {
            guard currentPage == page else { return }
            facingContent = Content(cached)
            return
        }
        guard let fetched = try? await pageContent(info, page: facing) else {
            facingContent = nil
            return
        }
        await pageCache.store(fetched, for: facing)
        guard currentPage == page else { return }
        facingContent = Content(fetched)
    }

    /// Only a text derivative of a paginated source carries page offsets; a
    /// plain .txt or .md has none and stays a single continuous body.
    var supportsTextPaging: Bool { textPageRanges.count > 1 }

    var textPageCount: Int { max(textPageRanges.count, 1) }

    /// A text book with no server pages: it is paginated on the device for
    /// the screen it is read on, and its place is a character offset.
    var isReflowableText: Bool { hasTextBody && !supportsTextPaging }

    /// Paged reading of a reflowable text book, which the view paginates.
    var usesLayoutPaging: Bool { isReflowableText && isTextPaged }

    var canToggleTextPaging: Bool { supportsTextPaging || isReflowableText }

    /// Where a bookmark in a text book points: the offset of the place on
    /// screen. `nil` for anything with real page numbers.
    var bookmarkCharOffset: Int? { isReflowableText ? textOffset : nil }

    /// Called by the view each time it finishes paginating. The reader stays
    /// on the page holding the same character offset; nothing is saved,
    /// because the place has not moved.
    func applyTextLayout(_ layout: TextPageMap) {
        guard isReflowableText else { return }
        textLayout = layout
        currentPage = layout.page(containing: textOffset)
    }

    /// Called by the continuous text view as the first visible block changes.
    func textDidScroll(to offset: Int) {
        guard isReflowableText, !isTextPaged else { return }
        let bounded = min(max(offset, 0), textLength)
        guard bounded != textOffset else { return }
        textOffset = bounded
        if let textLayout { currentPage = textLayout.page(containing: bounded) }
        schedulePositionSave()
    }

    private var visibleText: String {
        guard isTextPaged, supportsTextPaging else { return fullText }
        return TextPagination.page(currentPage, in: fullText, ranges: textPageRanges)
    }

    /// Switches between one continuous body and page-at-a-time reading. The
    /// page number is preserved, so leaving paged mode and returning lands
    /// where the reader was.
    func setTextPaged(_ paged: Bool) {
        guard paged != isTextPaged, canToggleTextPaging else { return }
        if isReflowableText {
            // The offset is the place in both modes; only the page it falls
            // on needs finding again.
            isTextPaged = paged
            if paged, let textLayout {
                currentPage = textLayout.page(containing: textOffset)
            }
            return
        }
        isTextPaged = paged
        if paged {
            currentPage = min(max(currentPage, 1), textPageCount)
        }
        refreshVisibleText()
        schedulePositionSave()
    }

    private func refreshVisibleText() {
        guard case let .text(_, isMarkdown) = content else { return }
        content = .text(visibleText, isMarkdown: isMarkdown)
    }

    /// Deny-by-default, and only for a document the app actually holds whole:
    /// per-page delivery never yields a complete file to hand over.
    var canExportDocument: Bool {
        guard info?.rights.canDownloadFile == true else { return false }
        switch info?.resource {
        case .fullPDF, .epub: return true
        default: return false
        }
    }

    var canPrintDocument: Bool {
        guard info?.rights.canPrint == true, info?.resource == .fullPDF else { return false }
        if case .pdf = content { return true }
        return false
    }

    var exportFileName: String {
        let title = info?.book.title ?? L("Без назви")
        return "\(title).\(exportPathExtension)"
    }

    private var exportPathExtension: String {
        info?.resource == .epub ? "epub" : "pdf"
    }

    /// Writes the in-hand document to protected temporary storage so the share
    /// sheet has a file to offer. Runs once per reader, and only if the rights
    /// actually allow it.
    private func prepareExportIfPermitted() {
        guard canExportDocument, exportableDocument == nil, exportTask == nil else { return }
        let bytes: Data?
        switch content {
        case let .pdf(data, _): bytes = data
        case let .epub(payload): bytes = payload.data
        default: bytes = nil
        }
        guard let bytes else { return }
        let id = fileID
        let pathExtension = exportPathExtension
        exportTask = Task { [weak self] in
            let url = try? await ProtectedTemporaryFile.write(
                bytes,
                fileID: id,
                pathExtension: pathExtension
            )
            await MainActor.run { self?.exportableDocument = url }
        }
    }

    /// Printing is offered only for a full PDF the rights allow: a per-page
    /// render is not the document, and the app must not assemble one.
    func printDocument() {
        guard canPrintDocument, case let .pdf(data, _) = content else { return }
        let controller = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = info?.book.title ?? L("Беринда")
        controller.printInfo = printInfo
        controller.printingItem = data
        controller.present(animated: true, completionHandler: nil)
    }

    func discardExportedDocument() {
        exportTask?.cancel()
        exportTask = nil
        ProtectedTemporaryFile.remove(exportableDocument)
        exportableDocument = nil
    }

    var canGoBackward: Bool { currentPage > 1 && !pageIsLoading }

    /// Pages come from the text derivative when reading paged text, and from
    /// the document itself otherwise.
    var navigablePageCount: Int? {
        if usesLayoutPaging { return textLayout?.pageCount }
        return isTextPaged && supportsTextPaging ? textPageCount : info?.totalPages
    }

    var canGoForward: Bool {
        guard !pageIsLoading, let total = navigablePageCount else { return false }
        // In spread mode the step is two, so a spread whose right half is
        // already the last page has nowhere further to go.
        return currentPage + pageStep <= total
    }

    var contents: [ReaderContentsItem] {
        guard let info, info.isPagedDocument else { return [] }
        return ReaderNavigation.contents(
            from: info.toc,
            workID: info.workID,
            totalPages: info.totalPages
        )
    }

    func pageLabel(for page: Int) -> String? {
        // Screen pages of a reflowed text have no printed counterpart.
        guard !isReflowableText else { return nil }
        return ReaderNavigation.pageLabel(for: page, in: info?.pageLabels ?? [])
    }

    /// Called by the publication reader as the reader moves. Cheap: it only
    /// records the position, leaving the quiet-interval save to decide when to
    /// send it.
    func publicationDidMove(to locator: ReadingLocator) {
        publicationLocator = locator
        schedulePositionSave()
    }

    func flushPosition() async {
        saveTask?.cancel()
        saveTask = nil
        await persistPosition()
    }

    private func loadContent(for info: ReaderInfo, local: LocalReadingPosition?) async throws {
        switch info.resource {
        case let .structuredText(isMarkdown):
            let response = try await repository.text(fileID: fileID)
            fullText = response.body
            hasTextBody = true
            textLength = response.body.utf16.count
            textPageRanges = TextPagination.pageRanges(
                in: response.body,
                offsets: response.pageOffsets
            )
            let restoredOffset = restoredTextOffset(from: info, local: local)
            textOffset = min(max(restoredOffset ?? 0, 0), textLength)
            if supportsTextPaging, let restoredOffset {
                // A `char` place (from the web reader or a char link) opens
                // on the server page that holds it.
                let starts = textPageRanges.map { response.body.utf16Offset(of: $0.lowerBound) }
                currentPage = TextPageMap(pageStarts: starts, textLength: textLength)
                    .page(containing: restoredOffset)
            }
            if isTextPaged, supportsTextPaging {
                currentPage = min(max(currentPage, 1), textPageRanges.count)
            }
            if isReflowableText {
                // Screen pages are counted once the view has paginated.
                currentPage = 1
            }
            content = .text(visibleText, isMarkdown: isMarkdown)
        case .fullPDF, .pagePDF, .pageImage:
            let fetched = try await pageContent(info, page: currentPage)
            await pageCache.store(fetched, for: currentPage)
            content = Content(fetched)
            prepareExportIfPermitted()
            prefetchNeighbours(around: currentPage, info: info)
        case .epub:
            guard (info.fileSizeBytes ?? 0) <= 100 * 1_024 * 1_024 else {
                throw APIError.responseTooLarge
            }
            content = .epub(
                EPUBPayload(data: try await repository.epubDocument(fileID: fileID))
            )
            prepareExportIfPermitted()
        case .unsupported:
            throw ReaderFailure.unsupported
        }
    }

    private func pageContent(_ info: ReaderInfo, page: Int) async throws -> ReaderPageContent {
        switch info.resource {
        case .fullPDF:
            return .pdf(
                try await repository.fullDocument(fileID: fileID),
                tracksDocumentPages: true
            )
        case .pagePDF:
            return .pdf(
                try await repository.pagePDF(fileID: fileID, page: page),
                tracksDocumentPages: false
            )
        case .pageImage:
            return .image(
                try await repository.pageImage(fileID: fileID, page: page, width: 1_600)
            )
        case .structuredText, .epub, .unsupported:
            throw ReaderFailure.unsupported
        }
    }

    private func reloadPage(_ requestedPage: Int) async {
        guard let info else { return }

        if let cached = await pageCache.content(for: requestedPage) {
            guard !Task.isCancelled, currentPage == requestedPage else { return }
            content = Content(cached)
            pageIsLoading = false
            await loadFacingPage(for: requestedPage, info: info)
            prefetchNeighbours(around: requestedPage, info: info)
            return
        }

        pageIsLoading = true
        defer {
            if currentPage == requestedPage { pageIsLoading = false }
        }
        do {
            let fetched = try await pageContent(info, page: requestedPage)
            await pageCache.store(fetched, for: requestedPage)
            guard !Task.isCancelled, currentPage == requestedPage else { return }
            content = Content(fetched)
            await loadFacingPage(for: requestedPage, info: info)
            prefetchNeighbours(around: requestedPage, info: info)
        } catch is CancellationError {
            return
        } catch {
            guard currentPage == requestedPage else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Warms at most the next and previous page — two, never a window that
    /// grows with reading speed — and only for pages not already cached.
    /// Prefetches are cancelled the moment the reader moves somewhere else, so
    /// a fast run of page turns cannot leave a queue of stale downloads behind.
    private func prefetchNeighbours(around page: Int, info: ReaderInfo) {
        let upperBound = info.totalPages
        let ahead = facingContent == nil ? page + 1 : page + 2
        let candidates = [ahead, page - 1].filter { candidate in
            guard candidate >= 1 else { return false }
            if let upperBound, candidate > upperBound { return false }
            return true
        }

        for (candidate, task) in prefetchTasks where !candidates.contains(candidate) {
            task.cancel()
            prefetchTasks[candidate] = nil
        }

        for candidate in candidates where prefetchTasks[candidate] == nil {
            prefetchTasks[candidate] = Task { [weak self] in
                await self?.prefetch(candidate, info: info)
            }
        }
    }

    private func prefetch(_ page: Int, info: ReaderInfo) async {
        defer { prefetchTasks[page] = nil }
        guard await pageCache.content(for: page) == nil else { return }
        guard let fetched = try? await pageContent(info, page: page) else { return }
        guard !Task.isCancelled else { return }
        await pageCache.store(fetched, for: page)
    }

    private func cancelPrefetches() {
        for task in prefetchTasks.values { task.cancel() }
        prefetchTasks.removeAll()
    }

    /// Backgrounding and memory pressure both drop the cache: every page is
    /// re-fetchable, so it is the cheapest thing to give up. The page on
    /// screen is kept, so returning to the app does not blank the reader.
    func releaseCachedPages() async {
        cancelPrefetches()
        facingContent = nil
        await pageCache.removeAll()
    }

    /// Re-fetches the current page if the reader came back to a view whose
    /// content was released while it was away.
    func recoverIfNeeded() async {
        guard case .none = content, phase.isLoaded, info != nil else { return }
        await reloadPage(currentPage)
    }

#if DEBUG
    /// Awaits the in-flight page load and every prefetch it started, so tests
    /// observe a settled reader instead of racing it.
    func settle() async {
        await pageTask?.value
        for task in Array(prefetchTasks.values) {
            await task.value
        }
    }

    var cachedPageCountForTesting: Int {
        get async { await pageCache.pageCount }
    }
#endif

    private func restoredPage(from info: ReaderInfo, local: LocalReadingPosition?) -> Int {
        if let initialPage {
            return min(max(initialPage, 1), max(info.totalPages ?? initialPage, 1))
        }
        let remotePage: Int?
        if info.readingPosition?.positionType == "page",
           let positionValue = info.readingPosition?.positionValue {
            remotePage = Int(positionValue)
        } else {
            remotePage = nil
        }
        // A record with a character offset belongs to a reflowed text, whose
        // page number was only a screen page; it is no document page.
        let localPage = local?.charOffset == nil ? local?.page : nil
        let page = remotePage ?? localPage ?? 1
        return min(max(page, 1), max(info.totalPages ?? page, 1))
    }

    /// A text book's place, from the most specific source that has one: a
    /// char link or bookmark, the server's `char` position, then the copy
    /// kept on the device. An explicit page link is not a text offset, and a
    /// `page` position for a text without server pages was never a real
    /// place (older builds always wrote page 1), so neither counts.
    private func restoredTextOffset(from info: ReaderInfo, local: LocalReadingPosition?) -> Int? {
        if let initialCharOffset { return initialCharOffset }
        if initialPage != nil { return nil }
        if let position = info.readingPosition, position.positionType == "char" {
            return Int(position.positionValue)
        }
        return local?.charOffset
    }

    private func schedulePositionSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.persistPosition()
        }
    }

    private func persistPosition() async {
        guard let info, phase.isLoaded else { return }
        guard account.profile?.readingHistoryEnabled != false, !serverDeclinedToRecord else {
            await localPositions.clearAll()
            return
        }
        let page = currentPage
        let total = info.totalPages
        if isReflowableText {
            await persistTextPosition(page: page)
            return
        }
        await localPositions.save(page: page, totalPages: total, for: fileID)

        guard await session.state() == .authenticated else { return }

        // A publication has no page number of its own — `currentPage` never
        // leaves 1 — so it sends a locator, the shape the web reader can also
        // read. Until the renderer reports one there is nothing to send:
        // writing a page number here is what used to destroy the reader's
        // position on every other client.
        if info.resource == .epub {
            guard let locator = publicationLocator,
                  locator.isRestorable,
                  let value = locator.encoded()
            else { return }
            let recordedLocator = await sendPosition(ReadingPositionUpdate(
                positionType: "locator",
                positionValue: value,
                progressPercent: locator.totalProgression.map {
                    min(max(Int(($0 * 100).rounded()), 0), 100)
                },
                totalPages: nil
            ))
            if !recordedLocator {
                serverDeclinedToRecord = true
                await localPositions.clearAll()
            }
            return
        }
        let progress = total.map { min(max(Int((Double(page) / Double(max($0, 1)) * 100).rounded()), 0), 100) }
        // A thrown error is a transient failure and says nothing about policy,
        // so only an explicit `recorded: false` counts as a refusal.
        let recorded = await sendPosition(ReadingPositionUpdate(
            positionType: "page",
            positionValue: String(page),
            progressPercent: progress,
            totalPages: total
        ))
        guard !recorded else { return }
        // The server keeps no history for this reader, so neither do we: the
        // local resume copy is dropped and nothing further is sent this
        // session. Same treatment the locally-known disabled policy gets.
        serverDeclinedToRecord = true
        await localPositions.clearAll()
    }
}

extension ReaderViewModel {
    /// A text book's place is a UTF-16 offset into its body (`char`), the
    /// shape the web reader writes and reads, with progress the share of the
    /// body before it. Screen pages are not sent: they differ per device.
    fileprivate func persistTextPosition(page: Int) async {
        let offset = textOffset
        await localPositions.save(
            page: page,
            totalPages: textLayout?.pageCount,
            charOffset: offset,
            for: fileID
        )
        guard await session.state() == .authenticated else { return }
        let progress = TextPageMap(pageStarts: [0], textLength: textLength).progressPercent(at: offset)
        let recorded = await sendPosition(ReadingPositionUpdate(
            positionType: "char",
            positionValue: String(offset),
            progressPercent: progress,
            totalPages: nil
        ))
        guard !recorded else { return }
        serverDeclinedToRecord = true
        await localPositions.clearAll()
    }

    /// Sends a position; `false` only for an explicit `recorded: false`.
    /// One that could not be sent — offline, or a server hiccup — is queued
    /// with the time it was reached, so a newer position saved elsewhere in
    /// the meantime still wins when the queue is flushed.
    fileprivate func sendPosition(_ update: ReadingPositionUpdate) async -> Bool {
        do {
            return try await repository.savePosition(
                fileID: fileID,
                positionType: update.positionType,
                positionValue: update.positionValue,
                progressPercent: update.progressPercent,
                totalPages: update.totalPages
            )
        } catch is CancellationError {
            return true
        } catch {
            if let offline, MutationOutbox.isTransient(error) {
                await offline.enqueue(
                    .readingPosition(fileID: fileID, update: update, clientUpdatedAt: Date()),
                    ownerID: account.profile?.id
                )
            }
            return true
        }
    }
}

private extension ReaderViewModel.Phase {
    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }
}

private enum ReaderFailure: LocalizedError {
    case restricted(String)
    case unsupported

    var errorDescription: String? {
        switch self {
        case let .restricted(reason): reason
        case .unsupported: L("Цей матеріал не підтримується в мобільному читачі.")
        }
    }
}
