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
        XCTAssertTrue(card("Лісова пісня").waitForExistence(timeout: 5))
        let toggle = app.switches["catalog.readable-only"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), app.debugDescription)
        flip(toggle, to: "1")
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: card("Лісова пісня"))
        waitForExpectations(timeout: 5)
        XCTAssertTrue(card("Кобзар").exists)
        XCTAssertFalse(card("Слово о полку Ігоревім").exists)
        flip(toggle, to: "0")
        XCTAssertTrue(card("Лісова пісня").waitForExistence(timeout: 5))
    }

    func testYearFilterIsShownAsAChipAndCanBeCleared() {
        XCTAssertTrue(card("Кобзар").waitForExistence(timeout: 5))
        let filters = app.buttons["catalog.filters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 5), app.debugDescription)
        filters.tap()

        let from = app.textFields["catalog.filters.year-from"]
        XCTAssertTrue(from.waitForExistence(timeout: 5), app.debugDescription)
        from.tap()
        from.typeText("1900")
        app.buttons["catalog.filters.apply"].tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: card("Кобзар"))
        waitForExpectations(timeout: 5)
        XCTAssertTrue(card("Лісова пісня").exists)
        XCTAssertTrue(app.buttons["catalog.filter.years"].exists)

        app.buttons["catalog.filters.clear"].tap()
        XCTAssertTrue(card("Кобзар").waitForExistence(timeout: 5))
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
        assertPagePosition("Сторінка 1 з 3, I")
    }

    /// `-ui.language en` sets the same preference as Profile → «Мова» (the
    /// launch argument wins over the stored value), so this is the English
    /// interface a reader gets after choosing English.
    func testEnglishInterfaceIsTranslated() {
        app.terminate()
        app.launchArguments += ["-ui.language", "en"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Catalog"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["Catalog"].exists)
        XCTAssertTrue(app.tabBars.buttons["Library"].exists)
        XCTAssertTrue(app.tabBars.buttons["Profile"].exists)
        let readable = app.switches["catalog.readable-only"]
        XCTAssertTrue(readable.waitForExistence(timeout: 5))
        XCTAssertTrue(readable.label.contains("Readable only"), readable.label)

        // Copy assembled as a String in code (the card's VoiceOver label, with
        // a plural) follows the choice as well as SwiftUI literals do.
        let kobzar = card("Кобзар")
        XCTAssertTrue(kobzar.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(kobzar.label.contains("1840, 1 edition, Public domain"), kobzar.label)
        kobzar.tap()
        XCTAssertTrue(app.staticTexts["Editions"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["work.quick-add"].label.contains("Add to List"), app.buttons["work.quick-add"].label)
        XCTAssertEqual(app.staticTexts["work.rights.title"].label, "Public domain")
        XCTAssertTrue(
            app.buttons["edition.read.\(EditionID.readable)"].label.contains("Read Edition"),
            app.buttons["edition.read.\(EditionID.readable)"].label
        )
        app.buttons["edition.read.\(EditionID.readable)"].tap()
        assertPagePosition("Page 1 of 3, I")
    }

    /// The VoiceOver journey of DEVICE-ACCEPTANCE.md §2, steps 1, 3 and 4, as
    /// far as XCUITest can see it: one labelled stop per work card, the work
    /// title and add-to-list control named, the reader's position spelled out
    /// on both the slider and the position text, and 44-point page buttons.
    func testMainJourneyIsLabelledForVoiceOver() {
        let kobzar = card("Кобзар")
        XCTAssertTrue(kobzar.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(kobzar.label.hasPrefix("Кобзар, Тарас Шевченко, 1840"), kobzar.label)
        XCTAssertTrue(kobzar.label.contains("Суспільне надбання"), kobzar.label)
        kobzar.tap()

        let title = app.staticTexts["work.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(title.label, "Кобзар")
        let addToList = app.buttons["work.quick-add"]
        XCTAssertTrue(addToList.exists)
        XCTAssertTrue(addToList.label.contains("До списку"), addToList.label)
        let edition = app.descendants(matching: .any)["work.edition.\(EditionID.readable)"]
        XCTAssertTrue(edition.waitForExistence(timeout: 5))
        XCTAssertTrue(edition.label.hasPrefix("Кобзар. Видання 1840 року"), edition.label)

        app.buttons["edition.read.\(EditionID.readable)"].tap()
        assertPagePosition("Сторінка 1 з 3, I")
        let slider = app.sliders["reader.page-slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        XCTAssertEqual(slider.value as? String, "Сторінка 1 з 3, I")
        let next = app.buttons["reader.next-page"]
        let previous = app.buttons["reader.previous-page"]
        XCTAssertEqual(next.label, "Наступна")
        XCTAssertEqual(previous.label, "Попередня")
        XCTAssertGreaterThanOrEqual(next.frame.width.rounded(), 44)
        XCTAssertGreaterThanOrEqual(next.frame.height.rounded(), 44)
        next.tap()
        assertPagePosition("Сторінка 2 з 3, II")
        XCTAssertEqual(slider.value as? String, "Сторінка 2 з 3, II")
        // The reading position is kept on the device across launches; leave
        // the book on page 1 for the journeys that expect to start there.
        previous.tap()
        assertPagePosition("Сторінка 1 з 3, I")
    }

    func testLaunchShowsAnonymousCatalog() {
        XCTAssertTrue(card("Кобзар").waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Каталог"].isSelected)
    }

    func testUkrainianSearchReturnsMatchingWork() {
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))

        searchField.tap()
        searchField.typeText("Кобзар")

        XCTAssertTrue(card("Кобзар").waitForExistence(timeout: 5))
        XCTAssertFalse(card("Лісова пісня").exists)
    }

    func testSearchShowsMatchingAuthorsAndOpensOne() {
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Шевченко")

        let tarasID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let author = app.buttons["catalog.author.\(tarasID)"]
        XCTAssertTrue(author.waitForExistence(timeout: 5), app.debugDescription)

        author.tap()
        let name = app.staticTexts["author.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.label, "Тарас Шевченко")
    }

    func testSearchShowsMatchingPeriodicalsAndOpensOne() {
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Шевченко")

        let periodicalID = UUID(uuidString: "99999999-0000-0000-0000-000000000001")!
        let periodical = app.buttons["catalog.periodical.\(periodicalID)"]
        XCTAssertTrue(periodical.waitForExistence(timeout: 5), app.debugDescription)
        periodical.tap()

        let name = app.staticTexts["periodical.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(name.label, "Шевченківський вісник")
    }

    func testPeriodicalsBrowseFromYearToIssueToItsWorks() {
        let periodicals = app.buttons["catalog.periodicals"]
        XCTAssertTrue(periodicals.waitForExistence(timeout: 5), app.debugDescription)
        periodicals.tap()

        let periodicalID = UUID(uuidString: "99999999-0000-0000-0000-000000000001")!
        let periodical = app.buttons["periodicals.periodical.\(periodicalID)"]
        XCTAssertTrue(periodical.waitForExistence(timeout: 5), app.debugDescription)
        periodical.tap()

        XCTAssertTrue(app.staticTexts["periodical.name"].waitForExistence(timeout: 5))
        let year = app.buttons["periodical.year.1925"]
        XCTAssertTrue(year.waitForExistence(timeout: 5), app.debugDescription)
        year.tap()

        let issueID = UUID(uuidString: "77777777-1925-0000-0000-000000000001")!
        let issue = app.buttons["periodical.issue.\(issueID)"]
        XCTAssertTrue(issue.waitForExistence(timeout: 5), app.debugDescription)
        issue.tap()

        XCTAssertTrue(app.staticTexts["issue.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["issue.title"].label, "1925, № 1")
        let kobzar = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let slovo = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        XCTAssertTrue(app.buttons["issue.work.\(kobzar)"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["issue.work.\(slovo)"].exists)
        app.buttons["issue.work.\(kobzar)"].tap()
        XCTAssertTrue(app.staticTexts["Видання"].waitForExistence(timeout: 5))
    }

    func testWorkPublishedInOpensItsIssue() {
        let work = card("Слово о полку Ігоревім")
        if !work.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        work.tap()

        let issueID = UUID(uuidString: "77777777-1925-0000-0000-000000000001")!
        let issue = app.buttons["work.issue.\(issueID)"]
        XCTAssertTrue(issue.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["work.periodical.shevchenkivskyi-visnyk"].exists)
        issue.tap()

        XCTAssertTrue(app.staticTexts["issue.title"].waitForExistence(timeout: 5))
    }

    func testCatalogLoadsTheNextPage() {
        let finalWork = card("Слово о полку Ігоревім")
        if !finalWork.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(finalWork.waitForExistence(timeout: 5))
    }

    func testReadableEditionOpensAndTurnsPage() {
        openWork(named: "Кобзар")

        XCTAssertTrue(
            app.descendants(matching: .any)["work.edition.\(EditionID.readable)"]
                .waitForExistence(timeout: 5)
        )
        let readButton = app.buttons["edition.read.\(EditionID.readable)"]
        XCTAssertTrue(readButton.waitForExistence(timeout: 5))
        readButton.tap()

        assertPagePosition("Сторінка 1 з 3, I")
        let nextButton = app.buttons["reader.next-page"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()
        assertPagePosition("Сторінка 2 з 3, II")
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
        // A card is one VoiceOver element, so its rights badge is part of
        // the card's label rather than an element of its own.
        let confirmed = card("Кобзар")
        XCTAssertTrue(confirmed.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmed.label.contains("Суспільне надбання"), confirmed.label)
        let unconfirmed = card("Лісова пісня")
        XCTAssertTrue(unconfirmed.waitForExistence(timeout: 5))
        XCTAssertFalse(unconfirmed.label.contains("Суспільне надбання"), unconfirmed.label)

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
        let work = card("Слово о полку Ігоревім")
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

    func testReadableEditionCanBeSavedForOfflineReading() {
        openWork(named: "Кобзар")
        let save = app.buttons["edition.save-offline.\(EditionID.readable)"]
        reveal(save)
        save.tap()

        let saved = app.descendants(matching: .any)["edition.saved-offline.\(EditionID.readable)"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10), app.debugDescription)

        app.tabBars.buttons["Профіль"].tap()
        let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let copy = app.descendants(matching: .any)["profile.offline.\(fileID)"]
        reveal(copy)
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

        let confirm = app.alerts.firstMatch.buttons["Видалити"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()

        let notice = app.alerts["Обліковий запис"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), app.debugDescription)
        notice.buttons["Гаразд"].tap()
        XCTAssertTrue(app.tabBars.buttons["Каталог"].isSelected)

        app.tabBars.buttons["Профіль"].tap()
        XCTAssertTrue(app.buttons["profile.authenticate"].waitForExistence(timeout: 5))
    }

    /// Signed out: rate the app with stars and a comment, then write to
    /// support, which refuses to send without a reply address.
    func testSignedOutReaderRatesTheAppAndWritesToSupport() {
        app.tabBars.buttons["Профіль"].tap()
        let rate = app.buttons["profile.feedback.rate"]
        reveal(rate)
        rate.tap()

        let stars = app.descendants(matching: .any)["feedback.rating"]
        XCTAssertTrue(stars.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(stars.label, "Оцінка")
        // The fifth star sits at the trailing end of the row.
        stars.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let deadline = Date().addingTimeInterval(5)
        while stars.value as? String != "5 з 5 зірок", Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertEqual(stars.value as? String, "5 з 5 зірок", stars.debugDescription)

        // A multi-line field is a text view, not a text field.
        let comment = app.descendants(matching: .any).matching(identifier: "feedback.message").firstMatch
        XCTAssertTrue(comment.waitForExistence(timeout: 5), app.debugDescription)
        comment.tap()
        comment.typeText("Дуже зручно читати")
        let send = app.buttons["feedback.send"]
        reveal(send)
        send.tap()
        XCTAssertTrue(app.descendants(matching: .any)["feedback.sent"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Дякуємо! Повідомлення надіслано."].exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let support = app.buttons["profile.feedback.support"]
        reveal(support)
        support.tap()
        let message = app.descendants(matching: .any).matching(identifier: "feedback.message").firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5), app.debugDescription)
        message.tap()
        message.typeText("Книжка не відкривається офлайн.")
        let supportSend = app.buttons["feedback.send"]
        reveal(supportSend)
        supportSend.tap()
        XCTAssertTrue(app.descendants(matching: .any)["feedback.error"].waitForExistence(timeout: 5), app.debugDescription)

        let email = app.textFields["feedback.email"]
        reveal(email)
        email.tap()
        email.typeText("reader@example.org")
        reveal(supportSend)
        supportSend.tap()
        XCTAssertTrue(app.descendants(matching: .any)["feedback.sent"].waitForExistence(timeout: 5), app.debugDescription)
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

    /// A catalog card. Each card is a single accessibility element labelled
    /// "title, authors, year, editions, rights", so it is found by the start
    /// of its label.
    private func card(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", title + ","))
            .firstMatch
    }

    /// The reader's position as VoiceOver reads it.
    private func assertPagePosition(_ spoken: String, file: StaticString = #filePath, line: UInt = #line) {
        let position = app.staticTexts["reader.page-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        // Polled rather than waited on with an expectation, so a mismatch
        // reports the label that was actually there.
        let deadline = Date().addingTimeInterval(10)
        while position.label != spoken, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertEqual(position.label, spoken, file: file, line: line)
    }

    private func openWork(named title: String) {
        let work = card(title)
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        work.tap()
        XCTAssertTrue(app.staticTexts["Видання"].waitForExistence(timeout: 5))
    }
}
