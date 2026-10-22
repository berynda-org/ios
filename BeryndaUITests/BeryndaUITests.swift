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
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), app.debugDescription)
        flip(toggle, to: "1")
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.staticTexts["Лісова пісня"])
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["Кобзар"].exists)
        XCTAssertFalse(app.staticTexts["Слово о полку Ігоревім"].exists)
        flip(toggle, to: "0")
        XCTAssertTrue(app.staticTexts["Лісова пісня"].waitForExistence(timeout: 5))
    }

    func testYearFilterIsShownAsAChipAndCanBeCleared() {
        XCTAssertTrue(app.staticTexts["Кобзар"].waitForExistence(timeout: 5))
        let filters = app.buttons["catalog.filters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 5), app.debugDescription)
        filters.tap()

        let from = app.textFields["catalog.filters.year-from"]
        XCTAssertTrue(from.waitForExistence(timeout: 5), app.debugDescription)
        from.tap()
        from.typeText("1900")
        app.buttons["catalog.filters.apply"].tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.staticTexts["Кобзар"])
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["Лісова пісня"].exists)
        XCTAssertTrue(app.buttons["catalog.filter.years"].exists)

        app.buttons["catalog.filters.clear"].tap()
        XCTAssertTrue(app.staticTexts["Кобзар"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["catalog.filter.years"].exists)
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

    func testSearchShowsMatchingAuthorsAndOpensOne() {
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Шевченко")

        let tarasID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let author = app.buttons["catalog.author.\(tarasID)"]
        XCTAssertTrue(author.waitForExistence(timeout: 5), app.debugDescription)
        // No periodical page exists yet, so a periodical hit is not offered.
        XCTAssertFalse(app.staticTexts["Шевченківський вісник"].exists)

        author.tap()
        let name = app.staticTexts["author.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.label, "Тарас Шевченко")
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
            app.buttons["work.topic.ukrainska-literatura"].label,
            "Українська література"
        )

        XCTAssertEqual(app.staticTexts["work.rights.title"].label, "Суспільне надбання")
        XCTAssertTrue(app.staticTexts["work.rights.explanation"].exists)
    }

    func testTopicsBrowseFromTheCatalogToATopicsWorks() {
        let topics = app.buttons["catalog.topics"]
        XCTAssertTrue(topics.waitForExistence(timeout: 5), app.debugDescription)
        topics.tap()

        let root = app.buttons["topics.topic.ukrainska-literatura"]
        XCTAssertTrue(root.waitForExistence(timeout: 5), app.debugDescription)
        root.tap()

        let name = app.staticTexts["topic.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.label, "Українська література")
        XCTAssertTrue(app.buttons["topic.child.poeziia"].waitForExistence(timeout: 5))
        let kobzar = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let forestSong = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        XCTAssertTrue(app.buttons["topic.work.\(kobzar)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["topic.work.\(forestSong)"].exists)
    }

    func testWorkTopicOpensTheTopicPage() {
        openWork(named: "Кобзар")
        let topic = app.buttons["work.topic.ukrainska-literatura"]
        XCTAssertTrue(topic.waitForExistence(timeout: 5))
        topic.tap()

        let name = app.staticTexts["topic.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.label, "Українська література")
        let kobzar = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        XCTAssertTrue(app.buttons["topic.work.\(kobzar)"].waitForExistence(timeout: 5))
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

    func testSignInSheetOffersEnabledSocialProvider() {
        app.tabBars.buttons["Профіль"].tap()
        let authenticate = app.buttons["profile.authenticate"]
        XCTAssertTrue(authenticate.waitForExistence(timeout: 5))
        authenticate.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["auth.apple"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.descendants(matching: .any)["auth.google"].waitForExistence(timeout: 5))
    }

    func testSocialConfigurationFailureCanBeRetried() {
        app.terminate()
        app.launchArguments.append("--ui-testing-social-failure")
        app.launch()
        app.tabBars.buttons["Профіль"].tap()
        let retry = app.buttons["auth.providers-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["auth.apple"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["auth.google"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["auth.providers-error"].exists)
    }

    func testLongCRLFTextBookDisplaysContent() {
        app.terminate()
        app.launchArguments.append("--ui-testing-long-text")
        app.launch()
        openWork(named: "Кобзар")
        app.buttons["edition.read.\(EditionID.readable)"].tap()
        let first = app.staticTexts["reader.text.block.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(first.label.hasPrefix("Тіні забутих предків."))
        XCTAssertTrue(first.isHittable)
        app.swipeUp()
        XCTAssertGreaterThan(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "reader.text.block.")).count, 1)
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

    func testSignedInReaderChangesPassword() {
        signInFromProfile()
        let link = app.buttons["profile.security.password"]
        reveal(link)
        link.tap()

        let current = app.secureTextFields["security.current-password"]
        XCTAssertTrue(current.waitForExistence(timeout: 5), app.debugDescription)
        current.tap()
        current.typeText("password123")
        let fresh = app.secureTextFields["security.new-password"]
        fresh.tap()
        fresh.typeText("a-new-password")
        let repeated = app.secureTextFields["security.repeat-password"]
        repeated.tap()
        repeated.typeText("a-new-password\n")

        let submit = app.buttons["security.change-password"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        submit.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["security.password-changed"].waitForExistence(timeout: 5),
            app.debugDescription
        )
    }

    func testSignedInReaderDeletesTheAccountWithAPassword() {
        signInFromProfile()
        let link = app.buttons["profile.security.delete"]
        reveal(link)
        link.tap()

        let password = app.secureTextFields["security.delete-password"]
        reveal(password)
        password.tap()
        password.typeText("password123\n")
        let delete = app.buttons["security.delete-with-password"]
        reveal(delete)
        delete.tap()

        let confirm = app.alerts.buttons["Видалити"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()

        let notice = app.alerts["Обліковий запис"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), app.debugDescription)
        notice.buttons["Гаразд"].tap()
        XCTAssertTrue(app.tabBars.buttons["Каталог"].isSelected)

        app.tabBars.buttons["Профіль"].tap()
        XCTAssertTrue(app.buttons["profile.authenticate"].waitForExistence(timeout: 5))
    }

    private func signInFromProfile() {
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
    }

    /// Lists build rows lazily, so a row below the fold does not exist until
    /// it has been scrolled to.
    private func reveal(_ element: XCUIElement) {
        var swipes = 0
        while !(element.exists && element.isHittable), swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription)
    }

    /// A labelled SwiftUI `Toggle` is one wide accessibility element, and
    /// `tap()` lands on its centre — the label — which does not flip it. The
    /// control itself sits at the trailing edge, so the tap is aimed there,
    /// and the new value is asserted so a tap that missed fails here rather
    /// than as a confusing timeout several lines later.
    private func flip(_ toggle: XCUIElement, to value: String) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let flipped = NSPredicate(format: "value == %@", value)
        expectation(for: flipped, evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
    }

    private func openWork(named title: String) {
        let work = app.staticTexts[title]
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        work.tap()
        XCTAssertTrue(app.staticTexts["Видання"].waitForExistence(timeout: 5))
    }
}
