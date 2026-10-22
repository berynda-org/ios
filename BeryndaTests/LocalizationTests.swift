import Foundation
import XCTest
import BeryndaCore
@testable import Berynda

/// The String Catalog is compiled into the app and the Profile language
/// choice reaches `String` copy, not only SwiftUI literals. (That every key
/// has an English translation is checked from the catalog's JSON by
/// `.github/scripts/check_strings_catalog.py` in CI.)
final class LocalizationTests: XCTestCase {
    private var previousLanguage: String?

    override func setUp() {
        super.setUp()
        previousLanguage = UserDefaults.standard.string(forKey: AppLanguage.storageKey)
    }

    override func tearDown() {
        if let previousLanguage {
            UserDefaults.standard.set(previousLanguage, forKey: AppLanguage.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        }
        super.tearDown()
    }

    func testCatalogIsCompiledForBothLanguages() {
        XCTAssertNotNil(Bundle.main.path(forResource: "en", ofType: "lproj"), "en.lproj missing from the app")
        XCTAssertNotNil(Bundle.main.path(forResource: "uk", ofType: "lproj"), "uk.lproj missing from the app")
    }

    func testStoredCodesNormalizeToASupportedLanguage() {
        XCTAssertEqual(AppLanguage(code: "en").rawValue, "en")
        XCTAssertEqual(AppLanguage(code: "en-GB").rawValue, "en")
        XCTAssertEqual(AppLanguage(code: "uk").rawValue, "uk")
        XCTAssertEqual(AppLanguage(code: nil).rawValue, "uk")
        XCTAssertEqual(AppLanguage(code: "de").rawValue, "uk")
    }

    func testEnglishChoiceTranslatesStringCopy() {
        UserDefaults.standard.set("en", forKey: AppLanguage.storageKey)
        XCTAssertEqual(AppLanguage.current, .english)
        XCTAssertEqual(AppLanguage.current.acceptLanguage, "en")
        XCTAssertEqual(L("Каталог"), "Catalog")
    }

    func testUkrainianChoiceKeepsTheSourceCopy() {
        UserDefaults.standard.set("uk", forKey: AppLanguage.storageKey)
        XCTAssertEqual(AppLanguage.current.acceptLanguage, "uk")
        XCTAssertEqual(L("Каталог"), "Каталог")
    }

    func testPluralsFollowEachLanguagesRules() {
        let one = 1, few = 3, many = 5
        UserDefaults.standard.set("uk", forKey: AppLanguage.storageKey)
        XCTAssertEqual(L("\(one) видань"), "1 видання")
        XCTAssertEqual(L("\(few) видань"), "3 видання")
        XCTAssertEqual(L("\(many) видань"), "5 видань")
        UserDefaults.standard.set("en", forKey: AppLanguage.storageKey)
        XCTAssertEqual(L("\(one) видань"), "1 edition")
        XCTAssertEqual(L("\(many) видань"), "5 editions")
    }

    func testCorePackageCopyFollowsTheChoice() {
        UserDefaults.standard.set("en", forKey: AppLanguage.storageKey)
        XCTAssertEqual(CoreLocalization.string("Матеріал не знайдено."), "Not found.")
        XCTAssertEqual(CatalogVocabulary.workTypeName("novel"), "Novel")
        UserDefaults.standard.set("uk", forKey: AppLanguage.storageKey)
        XCTAssertEqual(CatalogVocabulary.workTypeName("novel"), "Роман")
    }
}
