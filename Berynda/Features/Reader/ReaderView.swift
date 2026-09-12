import BeryndaCore
import PDFKit
import SwiftUI
import UIKit

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var model: ReaderViewModel
    @ObservedObject private var account: AccountViewModel
    @State private var showsContents = false
    @State private var showsAppearance = false
    @State private var draftPage = 1.0
    @State private var isScrubbing = false
    // Persisted, not per-presentation state: a reader who enlarges the text
    // once should not have to do it again on the next book.
    @AppStorage("reader.textScale") private var storedTextScale = 1.0
    @AppStorage("reader.lineSpacingScale") private var storedLineSpacingScale = 1.0
    @State private var saveMessage: String?
    private let fallbackTitle: String
    private let library: LibraryViewModel

    init(
        fileID: UUID,
        fallbackTitle: String,
        initialPage: Int? = nil,
        repository: any ReaderRepository,
        session: SessionController,
        account: AccountViewModel,
        localPositions: LocalReadingPositionStore,
        library: LibraryViewModel
    ) {
        self.fallbackTitle = fallbackTitle
        self.library = library
        _account = ObservedObject(wrappedValue: account)
        _model = StateObject(
            wrappedValue: ReaderViewModel(
                fileID: fileID,
                initialPage: initialPage,
                repository: repository,
                session: session,
                account: account,
                localPositions: localPositions
            )
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    ProgressView("Відкриваємо видання…")
                case let .failed(message):
                    ContentUnavailableView {
                        Label("Не вдалося відкрити", systemImage: "book.closed")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Спробувати ще раз") { Task { await model.load() } }
                    }
                case .loaded:
                    readerContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BeryndaColor.paper)
            .navigationTitle(model.info?.book.title ?? fallbackTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрити", systemImage: "xmark") { dismiss() }
                }
                if !model.contents.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Зміст", systemImage: "list.bullet.indent") {
                            showsContents = true
                        }
                        .accessibilityIdentifier("reader.contents")
                    }
                }
                if isTextReader {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Вигляд тексту", systemImage: "textformat.size") {
                            showsAppearance = true
                        }
                        .accessibilityIdentifier("reader.appearance")
                    }
                }
                if model.supportsTextPaging {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(
                            model.isTextPaged ? "Суцільний текст" : "Посторінково",
                            systemImage: model.isTextPaged ? "scroll" : "book.pages"
                        ) {
                            model.setTextPaged(!model.isTextPaged)
                            draftPage = Double(model.currentPage)
                        }
                        .accessibilityIdentifier("reader.text-paging")
                    }
                }
                if model.info?.rights.canShare == true {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: shareURL) {
                            Label("Поділитися", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                // Both affordances are deny-by-default: they appear only when
                // the API grants the right AND the whole document is actually
                // in hand. Per-page delivery has no complete file to give.
                if model.canExportDocument, let document = model.exportableDocument {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(
                            item: document,
                            preview: SharePreview(model.exportFileName)
                        ) {
                            Label("Зберегти файл", systemImage: "arrow.down.circle")
                        }
                        .accessibilityIdentifier("reader.download")
                    }
                }
                if model.canPrintDocument {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Друк", systemImage: "printer") {
                            model.printDocument()
                        }
                        .accessibilityIdentifier("reader.print")
                    }
                }
                // Shown to everyone: an anonymous reader is asked to sign in
                // and the bookmark lands once they have, like every other
                // protected action in the app.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закладка", systemImage: "bookmark") {
                        Task {
                            let page = model.currentPage
                            let result = await library.quickAdd(
                                fileID: model.fileID,
                                page: page
                            )
                            if result == .signInRequired {
                                environment.requireAuthentication(
                                    for: .bookmark(fileID: model.fileID, page: page)
                                )
                            } else {
                                saveMessage = result.message
                            }
                        }
                    }
                    .disabled(library.isMutating)
                    .accessibilityIdentifier("reader.bookmark")
                }
            }
        }
        .task { await model.load() }
        .sheet(isPresented: $showsContents) {
            ReaderContentsSheet(
                items: model.contents,
                currentPage: model.currentPage
            ) { page in
                model.selectPage(page)
                draftPage = Double(page)
                showsContents = false
            }
        }
        .sheet(isPresented: $showsAppearance) {
            ReaderAppearanceSheet(
                textScale: textScaleBinding,
                lineSpacingScale: lineSpacingScaleBinding
            )
        }
        // The root view's sign-in sheet sits under this full-screen cover and
        // cannot appear over it, so the reader presents it itself with the
        // same wiring; the pending bookmark resumes without leaving the book.
        .sheet(isPresented: $environment.showsAuthentication, onDismiss: {
            environment.authenticationDismissed()
        }) {
            AuthenticationView(
                account: environment.account,
                onAuthenticated: { await environment.resumePendingAuthenticatedAction() }
            )
        }
        .onChange(of: environment.authenticatedActionMessage) { _, message in
            // Same story for the root alert: surface the resumed action's
            // outcome in the reader's own alert instead.
            guard let message else { return }
            environment.authenticatedActionMessage = nil
            saveMessage = message
        }
        .onAppear { environment.isReaderPresented = true }
        .onChange(of: model.currentPage) { _, page in
            guard !isScrubbing else { return }
            draftPage = Double(page)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Coming back from a release: re-fetch only if the page on
                // screen was dropped while the app was away.
                Task { await model.recoverIfNeeded() }
                return
            }
            Task {
                await model.flushPosition()
                await model.releaseCachedPages()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didReceiveMemoryWarningNotification
            )
        ) { _ in
            Task { await model.releaseCachedPages() }
        }
        .onDisappear {
            environment.isReaderPresented = false
            model.discardExportedDocument()
            Task {
                await model.flushPosition()
                await model.releaseCachedPages()
            }
        }
        .alert("Бібліотека", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("Гаразд", role: .cancel) {}
        } message: {
            Text(saveMessage ?? "")
        }
        .accessibilityIdentifier("reader.\(model.fileID)")
    }

    @ViewBuilder
    private var readerContent: some View {
        GeometryReader { proxy in
            // A spread needs a regular width and a landscape shape: two pages
            // on a compact or portrait screen would be too small to read.
            let spread = horizontalSizeClass == .regular
                && proxy.size.width > proxy.size.height
                && model.supportsSpread
            spreadContent
                // GeometryReader aligns top-leading and does not stretch its
                // child, so the reader must be told to fill the pane it
                // measured or it would shrink-wrap its content.
                .frame(width: proxy.size.width, height: proxy.size.height)
                .task(id: spread) { await model.setSpreadEnabled(spread) }
        }
    }

    private var spreadContent: some View {
        VStack(spacing: 0) {
            Group {
                switch model.content {
                case let .text(body, isMarkdown):
                    TextReaderView(
                        content: body,
                        isMarkdown: isMarkdown,
                        allowsSelection: model.info?.rights.canCopyText == true,
                        textScale: textScale,
                        lineSpacingScale: lineSpacingScale
                    )
                case let .pdf(data, tracksDocumentPages):
                    if case let .pdf(facing, _)? = model.facingContent {
                        HStack(spacing: 0) {
                            PDFReaderView(
                                data: data,
                                currentPage: $model.currentPage,
                                tracksDocumentPages: false
                            )
                            PDFReaderView(
                                data: facing,
                                currentPage: .constant(1),
                                tracksDocumentPages: false
                            )
                        }
                        .accessibilityIdentifier("reader.spread")
                    } else {
                        PDFReaderView(
                            data: data,
                            currentPage: $model.currentPage,
                            tracksDocumentPages: tracksDocumentPages
                        )
                    }
                case let .image(data):
                    if case let .image(facing)? = model.facingContent {
                        HStack(spacing: 0) {
                            ServerPageImage(data: data, page: model.currentPage)
                            ServerPageImage(data: facing, page: model.currentPage + 1)
                        }
                        .accessibilityIdentifier("reader.spread")
                    } else {
                        ServerPageImage(data: data, page: model.currentPage)
                    }
                case let .epub(payload):
                    EPUBReaderView(
                        payload: payload,
                        fileID: model.fileID,
                        initialProgressPercent: model.info?.readingPosition?.progressPercent,
                        initialLocator: model.info?.readingPosition?.locator,
                        allowsCopy: model.info?.rights.canCopyText == true,
                        allowsShare: model.info?.rights.canShare == true,
                        onLocatorChange: { model.publicationDidMove(to: $0) },
                        onRetry: { Task { await model.load() } }
                    )
                case nil:
                    ProgressView()
                }
            }

            if showsPageControls {
                pageControls
            }
        }
    }

    private var showsPageControls: Bool {
        if model.isTextPaged, model.supportsTextPaging { return true }
        guard let info = model.info else { return false }
        return info.renderingMode == .pdf && (info.totalPages ?? 0) > 1
    }

    private var isTextReader: Bool {
        guard let mode = model.info?.renderingMode else { return false }
        return mode == .text || mode == .markdown
    }

    private var pageControls: some View {
        VStack(spacing: 5) {
            Slider(
                value: $draftPage,
                in: 1...Double(max(model.navigablePageCount ?? 1, 1)),
                step: 1
            ) { editing in
                isScrubbing = editing
                if !editing {
                    model.selectPage(Int(draftPage.rounded()))
                }
            }
            .disabled(model.pageIsLoading)
            .accessibilityLabel("Перейти до сторінки")
            .accessibilityValue(pageLabel(for: displayedPage))
            .accessibilityIdentifier("reader.page-slider")

            HStack(spacing: 18) {
                Button("Попередня", systemImage: "chevron.left") {
                    model.selectPage(model.currentPage - model.pageStep)
                }
                .labelStyle(.iconOnly)
                .disabled(!model.canGoBackward)
                .accessibilityIdentifier("reader.previous-page")

                if model.pageIsLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text(pageLabel(for: displayedPage))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(BeryndaColor.mutedInk)
                }

                Button("Наступна", systemImage: "chevron.right") {
                    model.selectPage(model.currentPage + model.pageStep)
                }
                .labelStyle(.iconOnly)
                .disabled(!model.canGoForward)
                .accessibilityIdentifier("reader.next-page")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var displayedPage: Int {
        isScrubbing ? Int(draftPage.rounded()) : model.currentPage
    }

    private func pageLabel(for page: Int) -> String {
        let prefix = model.pageLabel(for: page).map { "\($0) · " } ?? ""
        guard let total = model.info?.totalPages else { return "\(prefix)с. \(page)" }
        return "\(prefix)с. \(page) з \(total)"
    }

    private var textScale: CGFloat { CGFloat(storedTextScale) }
    private var lineSpacingScale: CGFloat { CGFloat(storedLineSpacingScale) }

    private var textScaleBinding: Binding<CGFloat> {
        Binding(
            get: { CGFloat(storedTextScale) },
            set: { storedTextScale = Double($0) }
        )
    }

    private var lineSpacingScaleBinding: Binding<CGFloat> {
        Binding(
            get: { CGFloat(storedLineSpacingScale) },
            set: { storedLineSpacingScale = Double($0) }
        )
    }

    private var shareURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "berynda.org"
        components.path = "/read/\(model.fileID.uuidString.lowercased())"
        if model.info?.renderingMode == .pdf {
            components.queryItems = [URLQueryItem(name: "p", value: String(model.currentPage))]
        }
        return components.url!
    }
}

private struct ReaderAppearanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var textScale: CGFloat
    @Binding var lineSpacingScale: CGFloat

    var body: some View {
        NavigationStack {
            Form {
                Section("Розмір тексту") {
                    Slider(value: $textScale, in: 0.85...1.4, step: 0.05) {
                        Text("Розмір тексту")
                    } minimumValueLabel: {
                        Image(systemName: "textformat.size.smaller")
                    } maximumValueLabel: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .accessibilityValue("\(Int((textScale * 100).rounded())) відсотків")
                }

                Section("Міжрядковий інтервал") {
                    Slider(value: $lineSpacingScale, in: 0.8...1.8, step: 0.1)
                        .accessibilityLabel("Міжрядковий інтервал")
                        .accessibilityValue("\(Int((lineSpacingScale * 100).rounded())) відсотків")
                }

                Button("Відновити стандартний вигляд") {
                    textScale = 1
                    lineSpacingScale = 1
                }
            }
            .navigationTitle("Вигляд тексту")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ReaderContentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let items: [ReaderContentsItem]
    let currentPage: Int
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            List(items) { item in
                Button {
                    onSelect(item.page)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(item.title)
                            .foregroundStyle(BeryndaColor.ink)
                            .padding(.leading, CGFloat(item.depth) * 16)
                        Spacer(minLength: 12)
                        Text("\(item.page)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(BeryndaColor.mutedInk)
                        if item.page == currentPage {
                            Image(systemName: "checkmark")
                                .foregroundStyle(BeryndaColor.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.title), сторінка \(item.page)")
            }
            .navigationTitle("Зміст")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct TextReaderView: View {
    let content: String
    let isMarkdown: Bool
    let allowsSelection: Bool
    let textScale: CGFloat
    let lineSpacingScale: CGFloat
    @ScaledMetric(relativeTo: .body) private var baseFontSize: CGFloat = 19
    @ScaledMetric(relativeTo: .body) private var baseLineSpacing: CGFloat = 7

    var body: some View {
        ScrollView {
            Group {
                if allowsSelection {
                    renderedText.textSelection(.enabled)
                } else {
                    renderedText
                }
            }
            .font(.system(size: baseFontSize * textScale, weight: .regular, design: .serif))
            .lineSpacing(baseLineSpacing * lineSpacingScale)
            .foregroundStyle(BeryndaColor.ink)
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
    }

    private var renderedText: Text {
        guard isMarkdown,
              let attributed = try? AttributedString(
                markdown: content,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
              )
        else { return Text(content) }
        return Text(attributed)
    }
}

private struct PDFReaderView: UIViewRepresentable {
    let data: Data
    @Binding var currentPage: Int
    let tracksDocumentPages: Bool

    func makeCoordinator() -> Coordinator { Coordinator(currentPage: $currentPage) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .clear
        view.displayDirection = .vertical
        view.displayMode = .singlePageContinuous
        view.usePageViewController(true, withViewOptions: nil)
        context.coordinator.observe(view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if context.coordinator.loadedData != data {
            context.coordinator.loadedData = data
            view.document = PDFDocument(data: data)
        }
        context.coordinator.tracksDocumentPages = tracksDocumentPages
        guard tracksDocumentPages,
              let document = view.document,
              currentPage > 0,
              currentPage <= document.pageCount,
              let target = document.page(at: currentPage - 1)
        else { return }
        if let visible = view.currentPage, document.index(for: visible) == currentPage - 1 { return }
        view.go(to: target)
    }

    final class Coordinator: NSObject {
        var loadedData: Data?
        var tracksDocumentPages = false
        private var currentPage: Binding<Int>
        private var observer: NSObjectProtocol?

        init(currentPage: Binding<Int>) {
            self.currentPage = currentPage
        }

        func observe(_ view: PDFView) {
            observer = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: view,
                queue: .main
            ) { [weak self, weak view] _ in
                guard let self, self.tracksDocumentPages,
                      let view, let document = view.document, let page = view.currentPage
                else { return }
                self.currentPage.wrappedValue = document.index(for: page) + 1
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
