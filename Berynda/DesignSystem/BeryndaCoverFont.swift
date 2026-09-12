import SwiftUI
import UIKit

/// The same Fedorovsk subset and fallback letters used by the website.
enum BeryndaCoverFont {
    static let postScriptName = "Fedorovsk-Regular"
    static func font(for glyph: String, size: CGFloat) -> Font {
        let fallback = Set("ЕЄЗ")
        if glyph.contains(where: { fallback.contains($0) }) {
            return .system(size: size, weight: .regular, design: .serif)
        }
        return .custom(postScriptName, fixedSize: size)
    }
}
