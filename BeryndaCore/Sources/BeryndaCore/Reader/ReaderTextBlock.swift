import Foundation

/// Bounded layout units for long plain-text and Markdown editions. Keep every
/// character, including CRLF and grapheme clusters, so rendering never truncates
/// a book or depends on the source using a particular paragraph separator.
public struct ReaderTextBlock: Identifiable, Sendable, Equatable {
    public let id: Int
    public let text: String

    public static func split(_ source: String, maximumCharacters: Int = 2_048) -> [Self] {
        guard !source.isEmpty else { return [] }
        let limit = max(1, maximumCharacters)
        var blocks: [Self] = []
        var start = source.startIndex
        var cursor = start
        var count = 0
        var offset = 0
        while cursor < source.endIndex {
            let character = source[cursor]
            cursor = source.index(after: cursor)
            count += 1
            if count >= limit || (character.isNewline && count >= min(512, limit)) {
                let text = String(source[start..<cursor])
                blocks.append(Self(id: offset, text: text))
                offset += text.utf16.count
                start = cursor
                count = 0
            }
        }
        if start < source.endIndex {
            blocks.append(Self(id: offset, text: String(source[start...])))
        }
        return blocks
    }
}
