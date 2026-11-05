import Foundation

/// Maps the `page_offsets` the API returns for a text derivative onto ranges
/// of the body it accompanies.
///
/// `page_offsets[i]` is the index at which page `i + 1` begins, counted the way
/// Python counts a `str`: in Unicode scalars. Neither Swift's `Character`
/// (grapheme clusters) nor `utf16` agrees with that in general, so the offsets
/// are walked over `unicodeScalars` deliberately — for Ukrainian text a
/// decomposed character or an emoji is enough to shift every later page.
///
/// The whole body is walked once and the boundaries kept as `String.Index`, so
/// turning a page is a substring rather than another scan of the book.
public enum TextPagination {
    /// One range per page, in order. Empty when the body has no pagination.
    public static func pageRanges(in text: String, offsets: [Int]) -> [Range<String.Index>] {
        let sanitised = sanitise(offsets, scalarCount: text.unicodeScalars.count)
        guard !sanitised.isEmpty else { return [] }

        var boundaries: [String.Index] = []
        boundaries.reserveCapacity(sanitised.count)

        let scalars = text.unicodeScalars
        var index = scalars.startIndex
        var scalarsSeen = 0
        var pointer = 0

        while pointer < sanitised.count {
            if scalarsSeen == sanitised[pointer] {
                boundaries.append(index)
                pointer += 1
                continue
            }
            guard index < scalars.endIndex else { break }
            index = scalars.index(after: index)
            scalarsSeen += 1
        }
        // An offset past the end of the body is clamped rather than dropped,
        // so a truncated derivative still yields a usable last page.
        while boundaries.count < sanitised.count {
            boundaries.append(text.endIndex)
        }

        return boundaries.indices.map { position in
            let start = boundaries[position]
            let end = position + 1 < boundaries.count ? boundaries[position + 1] : text.endIndex
            return start..<max(start, end)
        }
    }

    /// The text of `page` (1-based), or the whole body when it is not paginated.
    public static func page(_ page: Int, in text: String, ranges: [Range<String.Index>]) -> String {
        guard !ranges.isEmpty else { return text }
        let bounded = min(max(page, 1), ranges.count)
        return String(text[ranges[bounded - 1]])
    }

    /// Offsets arrive from the network, so they are treated as untrusted:
    /// negatives, duplicates, out-of-order entries, and anything past the end
    /// of the body would otherwise produce nonsense or crashing ranges.
    static func sanitise(_ offsets: [Int], scalarCount: Int) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(offsets.count)
        for offset in offsets {
            let clamped = min(max(offset, 0), scalarCount)
            guard let last = result.last else {
                result.append(clamped)
                continue
            }
            guard clamped > last else { continue }
            result.append(clamped)
        }
        // A body that does not start at zero would silently lose its opening.
        if let first = result.first, first != 0 {
            result.insert(0, at: 0)
        }
        return result
    }
}
