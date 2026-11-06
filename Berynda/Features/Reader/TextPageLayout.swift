import BeryndaCore
import UIKit

/// The geometry and type a text book is paginated for. Everything that
/// changes where a page breaks is in here, so a change to any of it — a
/// rotation, a larger text size, Dynamic Type — produces a new layout.
struct TextPageMetrics: Hashable, Sendable {
    /// The reader pane the pages are shown in.
    let paneWidth: CGFloat
    let paneHeight: CGFloat
    let fontSize: CGFloat
    let lineSpacing: CGFloat

    static let horizontalPadding: CGFloat = 24
    static let verticalPadding: CGFloat = 28
    static let maximumTextWidth: CGFloat = 720

    init(pane: CGSize, fontSize: CGFloat, lineSpacing: CGFloat) {
        // Whole points: a pane that wobbles by a fraction during a rotation
        // must not restart pagination for every intermediate frame.
        paneWidth = pane.width.rounded(.down)
        paneHeight = pane.height.rounded(.down)
        self.fontSize = (fontSize * 10).rounded() / 10
        self.lineSpacing = (lineSpacing * 10).rounded() / 10
    }

    /// Same measure as the scrolling reader: at most 720 points wide, inset
    /// 24 points from the sides and 28 from the top and bottom.
    var textWidth: CGFloat {
        max(min(paneWidth - 2 * Self.horizontalPadding, Self.maximumTextWidth), 0)
    }

    var textHeight: CGFloat {
        max(paneHeight - 2 * Self.verticalPadding, 0)
    }

    /// Too small to hold a line: the pane is still being laid out.
    var isUsable: Bool { textWidth >= 60 && textHeight >= 60 }
}

/// One finished pagination: the rendered text, the range of it each page
/// shows, and where each page starts in the source body.
final class TextPageLayout: @unchecked Sendable {
    let metrics: TextPageMetrics
    let attributedText: NSAttributedString
    /// Per page, in rendered (drawn) UTF-16 units.
    let renderedRanges: [NSRange]
    /// Per page, in source UTF-16 units — what positions and bookmarks store.
    let pageMap: TextPageMap

    init(metrics: TextPageMetrics, attributedText: NSAttributedString, renderedRanges: [NSRange], pageMap: TextPageMap) {
        self.metrics = metrics
        self.attributedText = attributedText
        self.renderedRanges = renderedRanges
        self.pageMap = pageMap
    }

    var pageCount: Int { renderedRanges.count }

    func text(ofPage page: Int) -> NSAttributedString {
        guard !renderedRanges.isEmpty else { return NSAttributedString() }
        let range = renderedRanges[min(max(page, 1), renderedRanges.count) - 1]
        return attributedText.attributedSubstring(from: range)
    }
}

/// Splits a text body into screen-sized pages with TextKit 1, the same engine
/// the page view draws with (`UITextView(usingTextLayoutManager: false)`), so
/// a page holds exactly the lines that fit on it.
///
/// TextKit 1 objects may be used off the main thread as long as one thread
/// owns them, which is how this runs: on a detached task, checking for
/// cancellation between pages so a rotation or text-size change abandons a
/// stale pass instead of finishing it.
enum TextPaginator {
    static func layout(
        body: String,
        isMarkdown: Bool,
        metrics: TextPageMetrics,
        progress: (Double) -> Void
    ) throws -> TextPageLayout {
        let (attributed, sourceMap) = attributedText(for: body, isMarkdown: isMarkdown, metrics: metrics)
        try Task.checkCancellation()

        let storage = NSTextStorage(attributedString: attributed)
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)

        // A couple of points short of the drawn height, so rounding in the
        // view can never push a page's last line out of sight.
        let containerSize = CGSize(width: metrics.textWidth, height: max(metrics.textHeight - 2, 1))
        let total = storage.length
        var ranges: [NSRange] = []
        var location = 0
        while location < total {
            let container = NSTextContainer(size: containerSize)
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            let glyphs = manager.glyphRange(for: container)
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            guard characters.length > 0, characters.location == location else {
                // A line taller than the page (an enormous text size) fits no
                // container; the rest becomes one last page rather than an
                // endless loop.
                ranges.append(NSRange(location: location, length: total - location))
                location = total
                break
            }
            ranges.append(characters)
            location = NSMaxRange(characters)
            if ranges.count % 16 == 0 {
                try Task.checkCancellation()
                progress(Double(location) / Double(max(total, 1)))
            }
        }
        if ranges.isEmpty {
            ranges = [NSRange(location: 0, length: total)]
        }
        progress(1)

        let starts = ranges.map { sourceMap.sourceOffset(forRendered: $0.location) }
        return TextPageLayout(
            metrics: metrics,
            attributedText: attributed,
            renderedRanges: ranges,
            pageMap: TextPageMap(pageStarts: starts, textLength: body.utf16.count)
        )
    }

    /// The text as drawn, plus the way back from drawn offsets to the source.
    /// Plain text is drawn untouched, character for character, so its offsets
    /// are the source's. Markdown is rendered block by block like the scrolling
    /// reader does, keeping a record of how long each block was before and
    /// after its markup was removed.
    static func attributedText(
        for body: String,
        isMarkdown: Bool,
        metrics: TextPageMetrics
    ) -> (NSAttributedString, TextSourceMap) {
        let base = baseAttributes(metrics)
        guard isMarkdown else {
            return (
                NSAttributedString(string: body, attributes: base),
                TextSourceMap.identity(length: body.utf16.count)
            )
        }
        let result = NSMutableAttributedString()
        var blocks: [(source: String, rendered: String)] = []
        for block in ReaderTextBlock.split(body) {
            let rendered = renderMarkdown(block.text, base: base, fontSize: metrics.fontSize)
            result.append(rendered)
            blocks.append((source: block.text, rendered: rendered.string))
        }
        return (result, TextSourceMap(blocks: blocks))
    }

    static func baseFont(size: CGFloat, traits: UIFontDescriptor.SymbolicTraits = []) -> UIFont {
        var descriptor = UIFont.systemFont(ofSize: size).fontDescriptor
        descriptor = descriptor.withDesign(.serif) ?? descriptor
        if !traits.isEmpty {
            descriptor = descriptor.withSymbolicTraits(traits) ?? descriptor
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func baseAttributes(_ metrics: TextPageMetrics) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = metrics.lineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: baseFont(size: metrics.fontSize),
            .foregroundColor: UIColor(BeryndaColor.ink),
            .paragraphStyle: paragraph,
        ]
    }

    /// Characters that can start inline Markdown. A block with none of them
    /// renders to itself, which skips the parser for most of a book.
    private static let markdownTriggers = CharacterSet(charactersIn: "*_`[]!<>\\&~")

    private static func renderMarkdown(
        _ source: String,
        base: [NSAttributedString.Key: Any],
        fontSize: CGFloat
    ) -> NSAttributedString {
        guard source.unicodeScalars.contains(where: { markdownTriggers.contains($0) }),
              let parsed = try? AttributedString(
                markdown: source,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
              )
        else { return NSAttributedString(string: source, attributes: base) }

        let result = NSMutableAttributedString()
        for run in parsed.runs {
            var attributes = base
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) {
                    attributes[.font] = UIFont.monospacedSystemFont(ofSize: fontSize * 0.9, weight: .regular)
                } else {
                    var traits: UIFontDescriptor.SymbolicTraits = []
                    if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                    if intent.contains(.emphasized) { traits.insert(.traitItalic) }
                    if !traits.isEmpty {
                        attributes[.font] = baseFont(size: fontSize, traits: traits)
                    }
                }
                if intent.contains(.strikethrough) {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
            }
            if let link = run.link {
                attributes[.link] = link
            }
            result.append(NSAttributedString(
                string: String(parsed[run.range].characters),
                attributes: attributes
            ))
        }
        return result
    }
}
