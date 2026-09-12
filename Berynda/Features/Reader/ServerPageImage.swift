import SwiftUI
import UIKit

struct ServerPageImage: UIViewRepresentable {
    let data: Data
    let page: Int

    func makeUIView(context: Context) -> ReaderPageScrollView {
        ReaderPageScrollView()
    }

    func updateUIView(_ view: ReaderPageScrollView, context: Context) {
        view.setPage(data: data, page: page)
    }
}

/// UIKit owns the pinch focal point, simultaneous panning and deceleration.
/// SwiftUI updates only replace the image when the displayed page changes.
final class ReaderPageScrollView: UIScrollView, UIScrollViewDelegate {
    let pageImageView = UIImageView()
    private let errorLabel = UILabel()
    private var loadedData: Data?
    private var loadedPage: Int?
    private var viewportSize = CGSize.zero
    private var needsPageLayout = false
    private var isLayingOutPage = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        accessibilityIdentifier = "reader.page-image"

        pageImageView.contentMode = .scaleAspectFit
        addSubview(pageImageView)

        errorLabel.text = "Сторінку пошкоджено"
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        addSubview(errorLabel)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(didDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setPage(data: Data, page: Int) {
        guard loadedData != data || loadedPage != page else { return }
        // Decoding is independent of gesture updates, including SwiftUI redraws.
        if loadedData != data { pageImageView.image = UIImage(data: data) }
        loadedData = data
        loadedPage = page
        needsPageLayout = true
        errorLabel.isHidden = pageImageView.image != nil
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !isLayingOutPage, bounds.width > 0, bounds.height > 0 else { return }
        errorLabel.frame = bounds
        guard needsPageLayout || viewportSize != bounds.size else { return }
        isLayingOutPage = true
        defer { isLayingOutPage = false }

        let restorePosition = !needsPageLayout && viewportSize != .zero
        let previousZoom = zoomScale
        // Use the previous viewport size: bounds already contains the new size
        // during rotation or an iPad split-view resize.
        let oldCenter = CGPoint(
            x: contentOffset.x + viewportSize.width / 2,
            y: contentOffset.y + viewportSize.height / 2
        )
        let imagePoint = pageImageView.convert(oldCenter, from: self)
        let oldImageSize = pageImageView.bounds.size
        let relativeCenter = CGPoint(
            x: oldImageSize.width > 0 ? imagePoint.x / oldImageSize.width : 0.5,
            y: oldImageSize.height > 0 ? imagePoint.y / oldImageSize.height : 0.5
        )
        viewportSize = bounds.size
        needsPageLayout = false

        setZoomScale(1, animated: false)
        let imageSize = pageImageView.image?.size ?? .zero
        guard imageSize.width > 0, imageSize.height > 0 else {
            pageImageView.frame = .zero
            contentSize = .zero
            contentInset = .zero
            contentOffset = .zero
            return
        }
        let fit = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * fit, height: imageSize.height * fit)
        pageImageView.frame = CGRect(origin: .zero, size: fittedSize)
        contentSize = fittedSize
        if restorePosition { setZoomScale(previousZoom, animated: false) }
        centerPage()

        if restorePosition {
            let center = pageImageView.convert(CGPoint(
                x: relativeCenter.x * fittedSize.width,
                y: relativeCenter.y * fittedSize.height
            ), to: self)
            contentOffset = boundedOffset(CGPoint(
                x: center.x - bounds.width / 2,
                y: center.y - bounds.height / 2
            ))
        } else {
            contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        pageImageView.image == nil ? nil : pageImageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard !isLayingOutPage else { return }
        centerPage()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        centerPage()
    }

    private func centerPage() {
        let horizontal = max((bounds.width - contentSize.width) / 2, 0)
        let vertical = max((bounds.height - contentSize.height) / 2, 0)
        let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != inset { contentInset = inset }
    }

    private func boundedOffset(_ proposed: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(proposed.x, -contentInset.left),
                   max(-contentInset.left, contentSize.width - bounds.width + contentInset.right)),
            y: min(max(proposed.y, -contentInset.top),
                   max(-contentInset.top, contentSize.height - bounds.height + contentInset.bottom))
        )
    }

    @objc private func didDoubleTap(_ gesture: UITapGestureRecognizer) {
        toggleZoom(at: gesture.location(in: pageImageView), animated: !UIAccessibility.isReduceMotionEnabled)
    }

    /// The tap is in image coordinates, matching UIScrollView.zoom(to:).
    func toggleZoom(at point: CGPoint, animated: Bool) {
        guard pageImageView.image != nil else { return }
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: animated)
        } else {
            let targetScale = min(2, maximumZoomScale)
            let size = CGSize(width: bounds.width / targetScale, height: bounds.height / targetScale)
            zoom(to: CGRect(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2,
                width: size.width,
                height: size.height
            ), animated: animated)
        }
    }
}
