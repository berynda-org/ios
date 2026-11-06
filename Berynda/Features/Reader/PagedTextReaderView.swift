import BeryndaCore
import SwiftUI
import UIKit

/// A plain-text or Markdown book shown one screen-sized page at a time, like
/// the web reader: swipe or tap the outer edges to turn, the page slider and
/// buttons below work as they do for a PDF.
///
/// The book is paginated for the pane it is shown in, off the main thread;
/// the pagination is redone when the pane, the text size, the line spacing or
/// Dynamic Type changes, and the reader stays on the same character offset.
struct PagedTextReaderView: View {
    let text: String
    let isMarkdown: Bool
    let allowsSelection: Bool
    let textScale: CGFloat
    let lineSpacingScale: CGFloat
    @ObservedObject var model: ReaderViewModel
    @ScaledMetric(relativeTo: .body) private var baseFontSize: CGFloat = 19
    @ScaledMetric(relativeTo: .body) private var baseLineSpacing: CGFloat = 7
    @StateObject private var pagination = TextPaginationState()

    init(
        text: String,
        isMarkdown: Bool,
        allowsSelection: Bool,
        textScale: CGFloat,
        lineSpacingScale: CGFloat,
        model: ReaderViewModel
    ) {
        self.text = text
        self.isMarkdown = isMarkdown
        self.allowsSelection = allowsSelection
        self.textScale = textScale
        self.lineSpacingScale = lineSpacingScale
        self.model = model
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = TextPageMetrics(
                pane: proxy.size,
                fontSize: baseFontSize * textScale,
                lineSpacing: baseLineSpacing * lineSpacingScale
            )
            ZStack {
                if let layout = pagination.layout {
                    TextPagerView(
                        layout: layout,
                        currentPage: model.currentPage,
                        allowsSelection: allowsSelection,
                        onPageChange: { model.selectPage($0) }
                    )
                    if pagination.isWorking {
                        // A re-pagination after a rotation or a text-size
                        // change: the old pages stay readable meanwhile.
                        ProgressView()
                            .controlSize(.small)
                            .padding(10)
                            .background(.regularMaterial, in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, 8)
                            .accessibilityLabel(Text("Розбиваємо текст на сторінки…"))
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView(value: pagination.progress)
                            .frame(maxWidth: 240)
                        Text("Розбиваємо текст на сторінки…")
                            .font(.footnote)
                            .foregroundStyle(BeryndaColor.mutedInk)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("reader.text.paginating")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: TextPaginationKey(metrics: metrics, isMarkdown: isMarkdown, length: text.utf16.count)) {
                guard metrics.isUsable else { return }
                if let layout = await pagination.paginate(text: text, isMarkdown: isMarkdown, metrics: metrics) {
                    model.applyTextLayout(layout.pageMap)
                }
            }
        }
    }
}

private struct TextPaginationKey: Hashable {
    let metrics: TextPageMetrics
    let isMarkdown: Bool
    let length: Int
}

@MainActor
final class TextPaginationState: ObservableObject {
    @Published private(set) var layout: TextPageLayout?
    @Published private(set) var progress: Double = 0
    @Published private(set) var isWorking = false
    private var generation = 0

    /// Paginates on a detached task; cancelling the caller (SwiftUI does when
    /// the key changes) cancels the pass. Returns the layout once it is shown.
    func paginate(text: String, isMarkdown: Bool, metrics: TextPageMetrics) async -> TextPageLayout? {
        if layout != nil {
            // Let a rotation or a dragged text-size slider settle first.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return nil }
        }
        generation += 1
        let pass = generation
        isWorking = true
        progress = 0
        let work = Task.detached(priority: .userInitiated) { [weak self] in
            try TextPaginator.layout(body: text, isMarkdown: isMarkdown, metrics: metrics) { value in
                Task { @MainActor [weak self] in
                    guard let self, self.isWorking else { return }
                    self.progress = value
                }
            }
        }
        let result = await withTaskCancellationHandler {
            try? await work.value
        } onCancel: {
            work.cancel()
        }
        // A newer pass owns the indicator; only the latest one clears it.
        if pass == generation { isWorking = false }
        guard !Task.isCancelled, let result else { return nil }
        layout = result
        return result
    }
}

/// Horizontal page turning over a `TextPageLayout`, one `UITextView` per page.
struct TextPagerView: UIViewControllerRepresentable {
    let layout: TextPageLayout
    let currentPage: Int
    let allowsSelection: Bool
    let onPageChange: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pager = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 24]
        )
        pager.dataSource = context.coordinator
        pager.delegate = context.coordinator
        pager.view.backgroundColor = .clear
        pager.view.accessibilityIdentifier = "reader.text.pager"
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        pager.view.addGestureRecognizer(tap)
        context.coordinator.pager = pager
        return pager
    }

    func updateUIViewController(_ pager: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.onPageChange = onPageChange
        let layoutChanged = coordinator.layout !== layout || coordinator.allowsSelection != allowsSelection
        coordinator.layout = layout
        coordinator.allowsSelection = allowsSelection
        let target = min(max(currentPage, 1), max(layout.pageCount, 1))
        guard let shown = coordinator.displayedPage, !layoutChanged else {
            coordinator.show(target, direction: .forward, animated: false)
            return
        }
        guard shown != target, !coordinator.isTransitioning else { return }
        coordinator.show(
            target,
            direction: target > shown ? .forward : .reverse,
            animated: abs(target - shown) == 1
        )
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate,
        UIGestureRecognizerDelegate {
        weak var pager: UIPageViewController?
        var layout: TextPageLayout?
        var allowsSelection = false
        var onPageChange: (Int) -> Void = { _ in }
        private(set) var isTransitioning = false

        var displayedPage: Int? {
            (pager?.viewControllers?.first as? TextPageController)?.page
        }

        func controller(for page: Int) -> TextPageController? {
            guard let layout, page >= 1, page <= layout.pageCount else { return nil }
            return TextPageController(
                layout: layout,
                page: page,
                allowsSelection: allowsSelection
            ) { [weak self] forward in
                self?.step(forward ? 1 : -1) ?? false
            }
        }

        func show(_ page: Int, direction: UIPageViewController.NavigationDirection, animated: Bool) {
            guard let pager, let controller = controller(for: page) else { return }
            isTransitioning = animated
            pager.setViewControllers([controller], direction: direction, animated: animated) { [weak self] _ in
                self?.isTransitioning = false
            }
        }

        /// One page forwards or backwards, as an edge tap or a VoiceOver
        /// three-finger swipe asks. `false` at either end of the book.
        @discardableResult
        func step(_ delta: Int) -> Bool {
            guard !isTransitioning, let shown = displayedPage else { return false }
            let target = shown + delta
            guard controller(for: target) != nil else { return false }
            show(target, direction: delta > 0 ? .forward : .reverse, animated: !UIAccessibility.isReduceMotionEnabled)
            onPageChange(target)
            return true
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view, view.bounds.width > 0 else { return }
            let x = recognizer.location(in: view).x
            if x < view.bounds.width * 0.25 {
                step(-1)
            } else if x > view.bounds.width * 0.75 {
                step(1)
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let page = (viewController as? TextPageController)?.page else { return nil }
            return controller(for: page - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let page = (viewController as? TextPageController)?.page else { return nil }
            return controller(for: page + 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            willTransitionTo pendingViewControllers: [UIViewController]
        ) {
            isTransitioning = true
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            isTransitioning = false
            guard completed, let page = displayedPage else { return }
            onPageChange(page)
        }
    }
}

/// One page of text, drawn by the same TextKit 1 engine that paginated it.
final class TextPageController: UIViewController {
    let page: Int
    private let layout: TextPageLayout
    private let allowsSelection: Bool
    private let onAccessibilityScroll: (Bool) -> Bool

    init(
        layout: TextPageLayout,
        page: Int,
        allowsSelection: Bool,
        onAccessibilityScroll: @escaping (Bool) -> Bool
    ) {
        self.layout = layout
        self.page = page
        self.allowsSelection = allowsSelection
        self.onAccessibilityScroll = onAccessibilityScroll
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let container = TextPageContainerView()
        container.onAccessibilityScroll = onAccessibilityScroll
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let textView = UITextView(usingTextLayoutManager: false)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.isSelectable = allowsSelection
        textView.dataDetectorTypes = []
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = false
        textView.attributedText = layout.text(ofPage: page)
        textView.accessibilityIdentifier = "reader.text.page.\(page)"
        view.addSubview(textView)

        let metrics = layout.metrics
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor, constant: TextPageMetrics.verticalPadding),
            textView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            textView.widthAnchor.constraint(equalToConstant: metrics.textWidth),
            textView.heightAnchor.constraint(equalToConstant: metrics.textHeight),
        ])
    }
}

/// Turns a VoiceOver three-finger swipe into a page turn. A swipe to the
/// left (scrolling right) or up (scrolling down) moves forward.
final class TextPageContainerView: UIView {
    var onAccessibilityScroll: (Bool) -> Bool = { _ in false }

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        switch direction {
        case .right, .down, .next:
            return onAccessibilityScroll(true)
        case .left, .up, .previous:
            return onAccessibilityScroll(false)
        @unknown default:
            return false
        }
    }
}
