import UIKit
import XCTest

/// Captures the shipping UI against the public production catalog. This target
/// is separate from deterministic CI tests and is run only by the store workflow.
final class AppStoreScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testUkrainianScreenshots() throws { try capture(locale: "uk", catalogTitle: "Каталог") }

    private func capture(locale: String, catalogTitle: String) throws {
        let app = XCUIApplication()
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
        app.launchArguments = [
            "-AppleLanguages", "(\(locale))", "-AppleLocale", locale == "uk" ? "uk_UA" : "en_US",
            "-ui.language", locale, "-appearance.mode", "light"
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars[catalogTitle].waitForExistence(timeout: 30))
        // Allow the live catalog and its cover images to finish rendering.
        Thread.sleep(forTimeInterval: 5)
        if !isPad { snapshot(app, locale, "01-catalog") }

        app.open(URL(string: "berynda://works/lisova-pisnia")!)
        XCTAssertTrue(app.buttons["work.quick-add"].waitForExistence(timeout: 45))
        XCTAssertTrue(app.staticTexts["work.bibliography.author"].waitForExistence(timeout: 45))
        Thread.sleep(forTimeInterval: 2)
        snapshot(app, locale, isPad ? "01-catalog-and-work" : "02-work")

        // Open a real readable edition through its visible control, just as a
        // reader does. Keep the production navigation path under test on iPad.
        let editionID = UUID(uuidString: "0f2a80aa-a6a6-5d8c-9e49-ee48d857b28e")!
        let read = app.buttons["edition.read.\(editionID)"]
        for _ in 0..<7 {
            if read.exists && read.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(read.waitForExistence(timeout: 30))
        read.tap()
        XCTAssertTrue(app.buttons["reader.next-page"].waitForExistence(timeout: 60))
        Thread.sleep(forTimeInterval: 2)
        snapshot(app, locale, "03-reader")
        let next = app.buttons["reader.next-page"]
        if next.isEnabled {
            next.tap()
            Thread.sleep(forTimeInterval: 2)
            snapshot(app, locale, "04-reading")
        }
        let contents = app.buttons["reader.contents"]
        if contents.exists && contents.isHittable {
            contents.tap()
            Thread.sleep(forTimeInterval: 1)
            snapshot(app, locale, "05-contents")
        }
        app.terminate()
    }

    private func snapshot(_ app: XCUIApplication, _ locale: String, _ name: String) {
        XCTAssertFalse(app.alerts.firstMatch.exists, "Do not capture a blocking alert")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "store-\(locale)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
