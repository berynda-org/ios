import UIKit
import XCTest
@testable import Berynda

final class CoverFontTests: XCTestCase {
    func testProductionCoverFontIsRegisteredInApplicationBundle() {
        XCTAssertNotNil(UIFont(name: BeryndaCoverFont.postScriptName, size: 64))
        XCTAssertNotNil(Bundle.main.url(forResource: "Fedorovsk-glyphs", withExtension: "ttf"))
    }
}
