import UIKit
import XCTest
@testable import Berynda

final class ReaderPageScrollViewTests: XCTestCase {
    @MainActor
    func testPortraitPageStartsFittedAndCentered() {
        let view = makeView()
        XCTAssertEqual(view.zoomScale, 1)
        XCTAssertEqual(view.pageImageView.frame.width, 390, accuracy: 0.01)
        XCTAssertEqual(view.pageImageView.frame.height, 520, accuracy: 0.01)
        XCTAssertEqual(view.contentInset.top, 90, accuracy: 0.01)
        XCTAssertEqual(view.contentOffset.y, -90, accuracy: 0.01)
        XCTAssertTrue(view.viewForZooming(in: view) === view.pageImageView)
        XCTAssertNotNil(view.pinchGestureRecognizer)
    }

    @MainActor
    func testDoubleTapKeepsTheTappedAreaAtTheCenter() {
        let view = makeView()
        let point = CGPoint(x: 234, y: 312)
        view.toggleZoom(at: point, animated: false)
        view.layoutIfNeeded()

        XCTAssertEqual(view.zoomScale, 2, accuracy: 0.01)
        let visibleCenter = imagePointAtViewportCenter(view)
        XCTAssertEqual(visibleCenter.x, point.x, accuracy: 1)
        XCTAssertEqual(visibleCenter.y, point.y, accuracy: 1)
        XCTAssertGreaterThan(view.contentOffset.x, 0)
        XCTAssertGreaterThan(view.contentOffset.y, 0)
    }

    @MainActor
    func testRepeatedViewUpdatesAndPanningKeepZoomAndPosition() {
        let data = pageData()
        let view = makeView(data: data)
        view.setZoomScale(3, animated: false)
        view.contentOffset = CGPoint(x: 240, y: 300)
        let originalImage = view.pageImageView.image

        for _ in 0..<10 {
            view.setPage(data: data, page: 1)
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
        XCTAssertEqual(view.zoomScale, 3, accuracy: 0.01)
        XCTAssertEqual(view.contentOffset.x, 240, accuracy: 0.01)
        XCTAssertEqual(view.contentOffset.y, 300, accuracy: 0.01)
        XCTAssertTrue(view.pageImageView.image === originalImage)
    }

    @MainActor
    func testRotationKeepsZoomAndTheVisiblePageArea() {
        let view = makeView()
        view.setZoomScale(3, animated: false)
        view.contentOffset = CGPoint(x: 413.4, y: 586)
        let oldSize = view.pageImageView.bounds.size
        let oldCenter = imagePointAtViewportCenter(view)

        view.frame = CGRect(x: 0, y: 0, width: 700, height: 390)
        view.setNeedsLayout()
        view.layoutIfNeeded()

        let newSize = view.pageImageView.bounds.size
        let newCenter = imagePointAtViewportCenter(view)
        XCTAssertEqual(view.zoomScale, 3, accuracy: 0.01)
        XCTAssertEqual(newCenter.x / newSize.width, oldCenter.x / oldSize.width, accuracy: 0.01)
        XCTAssertEqual(newCenter.y / newSize.height, oldCenter.y / oldSize.height, accuracy: 0.01)
    }

    @MainActor
    func testNextPageResetsToFitEvenWhenTwoPagesHaveIdenticalPixels() {
        let data = pageData()
        let view = makeView(data: data)
        view.setZoomScale(3, animated: false)
        view.contentOffset = CGPoint(x: 200, y: 300)
        view.setPage(data: data, page: 2)
        view.layoutIfNeeded()

        XCTAssertEqual(view.zoomScale, 1, accuracy: 0.01)
        XCTAssertEqual(view.contentOffset.x, 0, accuracy: 0.01)
        XCTAssertEqual(view.contentOffset.y, -90, accuracy: 0.01)
    }

    @MainActor
    func testSecondDoubleTapReturnsToCenteredFit() {
        let view = makeView()
        view.toggleZoom(at: CGPoint(x: 234, y: 312), animated: false)
        view.toggleZoom(at: CGPoint(x: 234, y: 312), animated: false)
        view.layoutIfNeeded()

        XCTAssertEqual(view.zoomScale, 1, accuracy: 0.01)
        XCTAssertEqual(view.contentOffset.x, 0, accuracy: 1)
        XCTAssertEqual(view.contentOffset.y, -90, accuracy: 1)
    }

    @MainActor
    func testZoomingNearAnEdgeStaysWithinThePage() {
        let view = makeView()
        view.toggleZoom(at: CGPoint(x: 385, y: 515), animated: false)
        view.layoutIfNeeded()

        XCTAssertEqual(view.zoomScale, 2, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(view.contentOffset.x, 0)
        XCTAssertGreaterThanOrEqual(view.contentOffset.y, 0)
        XCTAssertLessThanOrEqual(view.contentOffset.x + view.bounds.width, view.contentSize.width + 1)
        XCTAssertLessThanOrEqual(view.contentOffset.y + view.bounds.height, view.contentSize.height + 1)
    }

    @MainActor
    func testCorruptPageClearsThePreviousImage() {
        let view = makeView()
        view.setZoomScale(2, animated: false)
        view.setPage(data: Data("invalid image".utf8), page: 2)
        view.layoutIfNeeded()

        XCTAssertNil(view.pageImageView.image)
        XCTAssertNil(view.viewForZooming(in: view))
        XCTAssertEqual(view.contentSize, .zero)
    }

    @MainActor
    private func makeView(data: Data? = nil) -> ReaderPageScrollView {
        let view = ReaderPageScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        view.setPage(data: data ?? pageData(), page: 1)
        view.layoutIfNeeded()
        return view
    }

    @MainActor
    private func imagePointAtViewportCenter(_ view: ReaderPageScrollView) -> CGPoint {
        view.pageImageView.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), from: view)
    }

    @MainActor
    private func pageData() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1600), format: format).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1600))
            UIColor.black.setFill()
            context.fill(CGRect(x: 100, y: 100, width: 1000, height: 30))
        }
    }
}
