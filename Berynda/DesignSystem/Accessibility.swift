import SwiftUI
import UIKit

/// VoiceOver announcements for results that arrive without moving focus:
/// a save that finished, an error under a form, a page turned by a button.
enum VoiceOver {
    /// Speaks `message` if VoiceOver is running; does nothing otherwise.
    @MainActor
    static func announce(_ message: String) {
        guard UIAccessibility.isVoiceOverRunning, !message.isEmpty else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

/// Smallest comfortable touch target (Apple HIG): 44 × 44 points.
enum BeryndaHitTarget {
    static let minimum: CGFloat = 44
}

@MainActor
extension View {
    /// Grows a small custom control's tappable area to 44 × 44 points without
    /// changing how it looks.
    func minimumHitTarget() -> some View {
        frame(minWidth: BeryndaHitTarget.minimum, minHeight: BeryndaHitTarget.minimum)
            .contentShape(Rectangle())
    }

    /// Announces `message` to VoiceOver whenever it changes to a non-empty
    /// value, e.g. an error shown under a form.
    func announcesChanges(of message: String?) -> some View {
        onChange(of: message) { _, newValue in
            if let newValue { VoiceOver.announce(newValue) }
        }
    }
}
