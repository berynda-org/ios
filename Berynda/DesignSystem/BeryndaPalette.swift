import Foundation

/// The raw palette, separate from the SwiftUI `Color` values built from it.
///
/// A resolved `Color` cannot be read back as a hex value, so keeping the
/// numbers here is what lets the palette be checked by a test rather than by
/// eye: that the dark set still matches the normative prototype, and that the
/// increased-contrast set still clears the ratios it claims to.
enum BeryndaPalette {
    struct Token: Equatable {
        let light: UInt
        let dark: UInt
        let lightIncreased: UInt
        let darkIncreased: UInt

        init(light: UInt, dark: UInt, lightIncreased: UInt? = nil, darkIncreased: UInt? = nil) {
            self.light = light
            self.dark = dark
            // A token with no dedicated high-contrast value keeps its standard
            // one, which is the correct behaviour for colours that already
            // carry enough contrast.
            self.lightIncreased = lightIncreased ?? light
            self.darkIncreased = darkIncreased ?? dark
        }
    }

    // Light and dark are taken from `web/public/ios-mockups/styles.css` — the
    // `:root` block and its `body[data-app-theme="dark"]` override.
    static let paper = Token(light: 0xF4F3ED, dark: 0x171312)
    static let surface = Token(light: 0xFFFDF8, dark: 0x211A18)
    static let ink = Token(light: 0x251F1D, dark: 0xF1EAE1)
    static let accent = Token(light: 0x95271D, dark: 0xE77B49)
    static let deepAccent = Token(light: 0x60241E, dark: 0xF1A37E)

    // The prototype defines no high-contrast palette, so these two carry this
    // client's own Increase Contrast values.
    static let mutedInk = Token(
        light: 0x6B6660,
        dark: 0xB4AAA0,
        lightIncreased: 0x4A4641,
        darkIncreased: 0xD6CEC5
    )
    static let border = Token(
        light: 0xD9D8CD,
        dark: 0x453A35,
        lightIncreased: 0x8D8C85,
        darkIncreased: 0x75635A
    )

    /// WCAG 2.1 relative luminance.
    static func relativeLuminance(_ hex: UInt) -> Double {
        func channel(_ value: UInt) -> Double {
            let normalised = Double(value) / 255
            return normalised <= 0.03928
                ? normalised / 12.92
                : pow((normalised + 0.055) / 1.055, 2.4)
        }
        let red = channel((hex >> 16) & 0xff)
        let green = channel((hex >> 8) & 0xff)
        let blue = channel(hex & 0xff)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    /// WCAG 2.1 contrast ratio, 1…21.
    static func contrastRatio(_ first: UInt, _ second: UInt) -> Double {
        let a = relativeLuminance(first)
        let b = relativeLuminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
