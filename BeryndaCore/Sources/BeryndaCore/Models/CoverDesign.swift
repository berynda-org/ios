import Foundation

/// The twelve canonical cover tones, in the order the web client fixed them.
///
/// Order is load-bearing: an absent `cover_tone` is derived by hashing the
/// work id into this list, so reordering or inserting anywhere but the end
/// would silently repaint existing works. Ported from `COVER_TONES` in
/// `web/src/components/catalog/catalogPresentation.ts` and kept in lockstep
/// with it by hand.
public enum CoverTone: String, CaseIterable, Sendable, Hashable {
    case oxblood
    case blue
    case green
    case ochre
    case plum
    case teal
    case slate
    case burgundy
    case moss
    case sepia
    case aubergine
    case graphite
}

/// Generated-cover layout templates. `plain` is the default until a work has
/// a design assigned, matching `workCoverVariant` on the web: nothing should
/// change visually until an editor actually picks a variant.
public enum CoverVariant: String, CaseIterable, Sendable, Hashable {
    case plain
    case label
    case frame
}

/// The resolved appearance of one work's cover.
///
/// Resolution is pure and seeded by the work id, so the same work renders
/// identically in the catalog list, on its detail page, and in the library —
/// and identically to the web client — with no shared state and no cache.
public struct CoverDesign: Sendable, Hashable {
    public let tone: CoverTone
    public let variant: CoverVariant
    /// The буквиця to draw, or `nil` when the title yields no usable letter.
    public let glyph: String?

    public init(tone: CoverTone, variant: CoverVariant, glyph: String?) {
        self.tone = tone
        self.variant = variant
        self.glyph = glyph
    }

    public static func resolve(
        workID: UUID,
        title: String,
        persistedTone: String?,
        persistedVariant: String?,
        persistedGlyph: String?
    ) -> CoverDesign {
        CoverDesign(
            tone: resolveTone(seed: seed(for: workID), persisted: persistedTone),
            variant: CoverVariant(rawValue: persistedVariant ?? "") ?? .plain,
            glyph: resolveGlyph(title: title, persisted: persistedGlyph)
        )
    }

    /// The seed the web hashes is the work id as the API serialises it:
    /// lowercase, hyphenated.
    public static func seed(for workID: UUID) -> String {
        workID.uuidString.lowercased()
    }

    static func resolveTone(seed: String, persisted: String?) -> CoverTone {
        // A stored design always wins outright; the hash is only a fallback
        // for works the backfill has not reached.
        if let persisted, let tone = CoverTone(rawValue: persisted) {
            return tone
        }
        let tones = CoverTone.allCases
        let index = Int(hash(seed) % UInt32(tones.count))
        return tones[index]
    }

    /// `hash = (hash * 31 + charCodeAt(i)) >>> 0` — the web's tone hash,
    /// reproduced exactly. `charCodeAt` yields UTF-16 code units and the
    /// arithmetic wraps at 32 bits, so both are matched deliberately rather
    /// than approximated with Swift's own hashing.
    static func hash(_ seed: String) -> UInt32 {
        var value: UInt32 = 0
        for unit in seed.utf16 {
            value = value &* 31 &+ UInt32(unit)
        }
        return value
    }

    /// Quotation marks and brackets a Ukrainian title commonly opens with
    /// carry no identity, so the glyph looks past them. Ported from
    /// `COVER_GLYPH_LEADING_SKIP_CHARS` on the web, itself a port of
    /// `_LEADING_SKIP_CHARS` in `apps/catalog/services/cover_glyph.py`.
    static let leadingSkipCharacters = Set("«»„\"“”‘’'‹›()[]{}")

    static func resolveGlyph(title: String, persisted: String?) -> String? {
        if let persisted, !persisted.trimmingCharacters(in: .whitespaces).isEmpty {
            return persisted
        }
        for character in title {
            if character.isWhitespace || leadingSkipCharacters.contains(character) {
                continue
            }
            // Digits are kept as-is and never cased, same as the server rule.
            return character.isNumber ? String(character) : String(character).uppercased()
        }
        return nil
    }
}

public extension WorkSummary {
    /// Stable cover appearance for this work, identical wherever it is drawn.
    var coverDesign: CoverDesign {
        CoverDesign.resolve(
            workID: id,
            title: title,
            persistedTone: coverTone,
            persistedVariant: coverVariant,
            persistedGlyph: coverGlyph
        )
    }
}

public extension CollectionWork {
    /// The same resolution as `WorkSummary.coverDesign`: a work shown in a
    /// collection strip must look identical to the same work in the catalog
    /// list, and both are seeded by the work id.
    var coverDesign: CoverDesign {
        CoverDesign.resolve(
            workID: id,
            title: title,
            persistedTone: coverTone,
            persistedVariant: coverVariant,
            persistedGlyph: coverGlyph
        )
    }
}
