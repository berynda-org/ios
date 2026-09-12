import Foundation
import XCTest

final class BeryndaUITests: XCTestCase {
    /// The edition identifiers `UITestRepository` serves. Interpolating the
    /// `UUID` rather than hardcoding a string keeps the case matching whatever
    /// `UUID.description` produces on both sides.
    private enum EditionID {
        static let readable = UUID(uuidString: "aaaaaaaa-1111-1111-1111-111111111111")!
        static let restricted = UUID(uuidString: "bbbbbbbb-2222-2222-2222-222222222222")!
        static let withoutFile = UUID(uuidString: "cccccccc-3333-3333-3333-333333333333")!
    }

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Каталог"].waitForExistence(timeout: 10))
    }

    func testReadingFilterHidesUnavailableWorksAndCanBeCleared() {
        XCTAssertTrue(app.staticTexts["Лісова пісня"].waitForExistence(timeout: 5))
        let toggle = app.switches["catalog.readable-only"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.staticTexts["Лісова пісня"])
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["Кобзар"].exists)
        XCTAssertFalse(app.staticTexts["Слово о полку Ігоревім"].exists)
        toggle.tap()
        XCTAssertTrue(app.staticTexts["Лісова пісня"].waitForExistence(timeout: 5))
    }

    func testAuthorNavigationOpensWorksAndReader() {
        openWork(named: "Кобзар")
        let authorID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let author = app.buttons["work.author.\(authorID)"]
        XCTAssertTrue(author.waitForExistence(timeout: 5))
        author.tap()
        XCTAssertTrue(app.staticTexts["author.name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["author.name"].label, "Тарас Шевченко")
        let workID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let work = app.buttons["author.work.\(workID)"]
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        work.tap()
        let read = app.buttons["edition.read.\(EditionID.readable)"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        read.tap()
        XCTAssertTrue(app.staticTexts["I · с. 1 з 3"].waitForExistence(timeout: 5))
    }

    func testLaunchShowsAnonymousCatalog() {
        XCTAssertTrue(app.staticTexts["Кобзар"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Каталог"].isSelected)
    }

    func testUkrainianSearchReturnsMatchingWork() {
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))

        searchField.tap()
        searchField.typeText("Кобзар")

        XCTAssertTrue(app.staticTexts["Кобзар"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Лісова пісня"].exists)
    }

    func testCatalogLoadsTheNextPage() {
        let finalWork = app.staticTexts["Слово о полку Ігоревім"]
        if !finalWork.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(finalWork.waitForExistence(timeout: 5))
    }

    func testReadableEditionOpensAndTurnsPage() {
        openWork(named: "Кобзар")

        XCTAssertTrue(
            app.staticTexts["work.edition.\(EditionID.readable)"]
                .waitForExistence(timeout: 5)
        )
        let readButton = app.buttons["edition.read.\(EditionID.readable)"]
        XCTAssertTrue(readButton.waitForExistence(timeout: 5))
        readButton.tap()

        XCTAssertTrue(app.staticTexts["I · с. 1 з 3"].waitForExistence(timeout: 5))
        let nextButton = app.buttons["reader.next-page"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()
        XCTAssertTrue(app.staticTexts["II · с. 2 з 3"].waitForExistence(timeout: 5))
    }

    func testWorkDetailShowsTheEnrichedBibliographyAndRights() {
        openWork(named: "Кобзар")

        // Contributor roles exist only on the detail record, so an "author"
        // row proves the thin list row was enriched rather than rendered as-is.
        let author = app.staticTexts["work.bibliography.author"]
        XCTAssertTrue(author.waitForExistence(timeout: 5))
        XCTAssertEqual(author.label, "Тарас Шевченко")

        let editor = app.staticTexts["work.bibliography.editor"]
        XCTAssertTrue(editor.exists)
        XCTAssertEqual(editor.label, "Іван Редактор")

        XCTAssertEqual(app.staticTexts["work.bibliography.kind"].label, "Поезія · збірка")
        XCTAssertEqual(app.staticTexts["work.bibliography.language"].label, "UK, RU")
        XCTAssertEqual(
            app.staticTexts["work.bibliography.topics"].label,
            "Українська література"
        )

        XCTAssertEqual(app.staticTexts["work.rights.title"].label, "Суспільне надбання")
        XCTAssertTrue(app.staticTexts["work.rights.explanation"].exists)
    }

    func testUnconfirmedPublicDomainClaimIsAbsentFromCatalogAndDetail() {
        let confirmedID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let unconfirmedID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        XCTAssertTrue(app.staticTexts["Кобзар"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["catalog.rights.\(confirmedID)"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["catalog.rights.\(unconfirmedID)"].exists)

        openWork(named: "Лісова пісня")
        XCTAssertTrue(app.staticTexts["edition.restricted.\(EditionID.restricted)"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["work.rights.title"].exists)
        XCTAssertFalse(app.staticTexts["work.rights.explanation"].exists)
    }

    func testRestrictedEditionExplainsWhyItCannotOpen() {
        openWork(named: "Лісова пісня")

        let restriction = app.staticTexts["edition.restricted.\(EditionID.restricted)"]
        XCTAssertTrue(restriction.waitForExistence(timeout: 5))
        // The reason is server-supplied, so asserting it stays safe under
        // localization; the read button must not exist at all.
        XCTAssertEqual(restriction.label, "Читання обмежено правовласником")
        XCTAssertFalse(app.buttons["edition.read.\(EditionID.restricted)"].exists)
    }

    func testEditionWithoutAFileDegradesSafely() {
        let work = app.staticTexts["Слово о полку Ігоревім"]
        if !work.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        work.tap()

        // The fallback copy here is app-owned and will move into the String
        // Catalog, so only its presence is asserted, by identifier.
        XCTAssertTrue(
            app.staticTexts["edition.restricted.\(EditionID.withoutFile)"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["edition.read.\(EditionID.withoutFile)"].exists)
    }

    func testSignInUnlocksProfileAndLibrary() {
        app.tabBars.buttons["Профіль"].tap()
        let authenticate = app.buttons["profile.authenticate"]
        XCTAssertTrue(authenticate.waitForExistence(timeout: 5))
        authenticate.tap()

        let email = app.textFields["auth.email"]
        let password = app.secureTextFields["auth.password"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("reader@example.org")
        password.tap()
        password.typeText("password123")
        app.buttons["auth.submit"].tap()

        XCTAssertTrue(app.buttons["Редагувати профіль"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Бібліотека"].tap()
        XCTAssertTrue(
            app.staticTexts["Відкрийте видання — воно з’явиться тут."]
                .waitForExistence(timeout: 5)
        )
    }

    func testSignInReturnsToPendingWorkSave() {
        openWork(named: "Кобзар")
        let save = app.buttons["work.quick-add"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        let email = app.textFields["auth.email"]
        let password = app.secureTextFields["auth.password"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("reader@example.org")
        password.tap()
        password.typeText("password123")
        app.buttons["auth.submit"].tap()

        XCTAssertTrue(
            app.staticTexts["Твір додано до бібліографічного списку."]
                .waitForExistence(timeout: 8)
        )
    }

    private func openWork(named title: String) {
        let work = app.staticTexts[title]
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        work.tap()
        XCTAssertTrue(app.staticTexts["Видання"].waitForExistence(timeout: 5))
    }
}
