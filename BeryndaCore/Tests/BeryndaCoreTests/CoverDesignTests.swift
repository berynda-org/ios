import Foundation
import XCTest
@testable import BeryndaCore

final class CoverDesignTests: XCTestCase {
    private let seed = "33333333-3333-3333-3333-333333333333"

    func testToneHashMatchesTheWebClient() {
        // Values produced by `workCoverToneClass`'s hash in
        // web/src/components/catalog/catalogPresentation.ts. If these drift,
        // the same work is painted differently on web and iOS.
        XCTAssertEqual(CoverDesign.hash("11111111-1111-1111-1111-111111111111"), 3_887_890_752)
        XCTAssertEqual(CoverDesign.hash(seed), 215_802_688)
        XCTAssertEqual(CoverDesign.hash("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"), 127_054_784)

        XCTAssertEqual(CoverDesign.resolveTone(seed: seed, persisted: nil), .plum)
        XCTAssertEqual(
            CoverDesign.resolveTone(seed: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", persisted: nil),
            .moss
        )
    }

    func testStoredToneWinsOverTheHash() {
        XCTAssertEqual(CoverDesign.resolveTone(seed: seed, persisted: "graphite"), .graphite)
        // An unknown tone from a newer API falls back to the hash rather than
        // to a single shared default.
        XCTAssertEqual(CoverDesign.resolveTone(seed: seed, persisted: "chartreuse"), .plum)
        XCTAssertEqual(CoverDesign.resolveTone(seed: seed, persisted: ""), .plum)
    }

    func testEveryToneHashesIntoTheFullPalette() {
        // A single default for untoned works would make a dense grid look
        // uniform, which is the whole reason the hash exists.
        var seen = Set<CoverTone>()
        for index in 0..<400 {
            seen.insert(CoverDesign.resolveTone(seed: "seed-\(index)", persisted: nil))
        }
        XCTAssertEqual(seen.count, CoverTone.allCases.count)
    }

    func testToneIsStableAcrossCalls() {
        let first = CoverDesign.resolveTone(seed: seed, persisted: nil)
        let second = CoverDesign.resolveTone(seed: seed, persisted: nil)
        XCTAssertEqual(first, second)
    }

    func testVariantDefaultsToPlainUntilOneIsAssigned() {
        XCTAssertEqual(design(variant: nil).variant, .plain)
        XCTAssertEqual(design(variant: "").variant, .plain)
        XCTAssertEqual(design(variant: "headpiece").variant, .plain)
        XCTAssertEqual(design(variant: "frame").variant, .frame)
        XCTAssertEqual(design(variant: "label").variant, .label)
    }

    func testGlyphSkipsLeadingQuotesAndBrackets() {
        XCTAssertEqual(CoverDesign.resolveGlyph(title: "«Лісова пісня»", persisted: nil), "Л")
        XCTAssertEqual(CoverDesign.resolveGlyph(title: "  (Нотатки)", persisted: nil), "Н")
        XCTAssertEqual(CoverDesign.resolveGlyph(title: "„Тіні“", persisted: nil), "Т")
    }

    func testGlyphKeepsDigitsUncased() {
        XCTAssertEqual(CoverDesign.resolveGlyph(title: "1984", persisted: nil), "1")
    }

    func testGlyphIsAbsentWhenTheTitleHasNoUsableCharacter() {
        XCTAssertNil(CoverDesign.resolveGlyph(title: "«»", persisted: nil))
        XCTAssertNil(CoverDesign.resolveGlyph(title: "   ", persisted: nil))
        XCTAssertNil(CoverDesign.resolveGlyph(title: "", persisted: nil))
    }

    func testStoredGlyphWins() {
        XCTAssertEqual(CoverDesign.resolveGlyph(title: "Енеїда", persisted: "Ⰵ"), "Ⰵ")
        XCTAssertEqual(CoverDesign.resolveGlyph(title: "Енеїда", persisted: "  "), "Е")
    }

    func testSeedIsTheLowercasedWorkID() {
        let id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        XCTAssertEqual(CoverDesign.seed(for: id), seed)
    }

    private func design(variant: String?) -> CoverDesign {
        CoverDesign.resolve(
            workID: UUID(uuidString: seed)!,
            title: "Лісова пісня",
            persistedTone: nil,
            persistedVariant: variant,
            persistedGlyph: nil
        )
    }
}
