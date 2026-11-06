import Foundation

/// Where each screen-sized page of a text book begins, as UTF-16 offsets into
/// the body exactly as the API returned it.
///
/// UTF-16 is the unit the web reader uses (a JavaScript string index), so a
/// `char` position or bookmark written here opens on the same text there and
/// the other way round. A `Character` count would drift on every CRLF, emoji
/// or combining mark; a scalar count on every emoji.
///
/// The starts arrive from layout, which never produces nonsense, but a map is
/// also rebuilt from stored values, so it is sanitised the same way either
/// way: clamped into the body, never decreasing, and always starting at 0.
/// The page count is never changed by sanitising, so it stays equal to the
/// number of pages the renderer actually drew.
public struct TextPageMap: Sendable, Equatable {
    public let pageStarts: [Int]
    /// Length of the body in UTF-16 code units.
    public let textLength: Int

    public init(pageStarts: [Int], textLength: Int) {
        let length = max(textLength, 0)
        var starts: [Int] = []
        starts.reserveCapacity(max(pageStarts.count, 1))
        for raw in pageStarts {
            guard let previous = starts.last else {
                starts.append(0)
                continue
            }
            starts.append(max(min(max(raw, 0), length), previous))
        }
        if starts.isEmpty { starts = [0] }
        self.pageStarts = starts
        self.textLength = length
    }

    public var pageCount: Int { pageStarts.count }

    /// The 1-based page whose text holds `offset`. Out-of-range offsets — a
    /// position saved against a longer or shorter edition of the body — land
    /// on the first or last page rather than failing.
    public func page(containing offset: Int) -> Int {
        let target = min(max(offset, 0), textLength)
        var low = 0
        var high = pageStarts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if pageStarts[middle] <= target {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low + 1
    }

    /// UTF-16 offset of the first character of `page` (1-based, clamped).
    public func startOffset(ofPage page: Int) -> Int {
        pageStarts[clamped(page) - 1]
    }

    /// UTF-16 offset just past the last character of `page` (1-based, clamped).
    public func endOffset(ofPage page: Int) -> Int {
        let bounded = clamped(page)
        return bounded < pageCount ? pageStarts[bounded] : textLength
    }

    /// How far into the body `offset` is, 0–100.
    public func progressPercent(at offset: Int) -> Int {
        guard textLength > 0 else { return 0 }
        let target = min(max(offset, 0), textLength)
        return min(max(Int((Double(target) / Double(textLength) * 100).rounded()), 0), 100)
    }

    private func clamped(_ page: Int) -> Int {
        min(max(page, 1), pageCount)
    }
}

/// Maps offsets in the text as it is drawn back to offsets in the source body.
///
/// Plain text is drawn as it is, so the map is the identity. Markdown loses
/// its markup when rendered (`**слово**` is drawn as «слово»), so a drawn
/// offset has to be translated before it can be saved: positions are always
/// stored against the source, the string the web reader also counts in.
///
/// The body is mapped block by block. Inside a block whose rendering equals
/// its source the mapping is exact; inside one that lost markup it is
/// proportional, which is off by at most the markup in that one block.
public struct TextSourceMap: Sendable, Equatable {
    public struct Segment: Sendable, Equatable {
        public let sourceStart: Int
        public let sourceLength: Int
        public let renderedStart: Int
        public let renderedLength: Int
    }

    public let segments: [Segment]

    public init(segments: [Segment]) {
        self.segments = segments
    }

    /// Builds the map from consecutive blocks, each given as its source text
    /// and the text it renders to. Lengths are counted in UTF-16.
    public init(blocks: [(source: String, rendered: String)]) {
        var segments: [Segment] = []
        segments.reserveCapacity(blocks.count)
        var source = 0
        var rendered = 0
        for block in blocks {
            let sourceLength = block.source.utf16.count
            let renderedLength = block.rendered.utf16.count
            segments.append(Segment(
                sourceStart: source,
                sourceLength: sourceLength,
                renderedStart: rendered,
                renderedLength: renderedLength
            ))
            source += sourceLength
            rendered += renderedLength
        }
        self.segments = segments
    }

    public static func identity(length: Int) -> TextSourceMap {
        TextSourceMap(segments: [
            Segment(sourceStart: 0, sourceLength: max(length, 0), renderedStart: 0, renderedLength: max(length, 0)),
        ])
    }

    public var sourceLength: Int {
        segments.last.map { $0.sourceStart + $0.sourceLength } ?? 0
    }

    public var renderedLength: Int {
        segments.last.map { $0.renderedStart + $0.renderedLength } ?? 0
    }

    /// The source offset a drawn offset corresponds to.
    public func sourceOffset(forRendered offset: Int) -> Int {
        guard !segments.isEmpty else { return 0 }
        let target = min(max(offset, 0), renderedLength)
        var low = 0
        var high = segments.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if segments[middle].renderedStart <= target {
                low = middle
            } else {
                high = middle - 1
            }
        }
        let segment = segments[low]
        let local = target - segment.renderedStart
        if local >= segment.renderedLength {
            return segment.sourceStart + segment.sourceLength
        }
        if segment.renderedLength == segment.sourceLength {
            return segment.sourceStart + local
        }
        let scaled = local * segment.sourceLength / segment.renderedLength
        return segment.sourceStart + min(max(scaled, 0), segment.sourceLength)
    }
}

public extension String {
    /// UTF-16 offset of `index`, the unit `char` positions are counted in.
    func utf16Offset(of index: String.Index) -> Int {
        utf16.distance(from: utf16.startIndex, to: index)
    }
}
