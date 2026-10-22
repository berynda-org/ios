import XCTest
@testable import BeryndaCore

/// The package's copy is Ukrainian unless the app installs a translator, and
/// the installed translator reaches vocabulary and format strings alike.
final class CoreLocalizationTests: XCTestCase {
    override func tearDown() {
        CoreLocalization.install { $0 }
        super.tearDown()
    }

    func testWithoutATranslatorTheSourceCopyIsUsed() {
        XCTAssertEqual(CoreLocalization.string("Матеріал не знайдено."), "Матеріал не знайдено.")
        XCTAssertEqual(CoreLocalization.format("з %@", "1925"), "з 1925")
    }

    func testInstalledTranslatorReachesVocabularyAndFormats() {
        CoreLocalization.install { key in
            switch key {
            case "Англійська": return "English"
            case "з %@": return "from %@"
            default: return key
            }
        }
        XCTAssertEqual(CatalogVocabulary.languageName("en"), "English")
        XCTAssertEqual(CoreLocalization.format("з %@", "1925"), "from 1925")
        // Unknown codes are still shown as themselves.
        XCTAssertEqual(CatalogVocabulary.languageName("xx"), "XX")
    }
}
