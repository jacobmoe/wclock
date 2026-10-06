import UIKit

/// Dims the screen, and puts the user's own brightness back afterwards.
@MainActor
final class ScreenDimmer {
    private static let dimmedLevel: CGFloat = 0.08
    private var savedLevel: CGFloat?

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.lazy.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    /// Safe to call repeatedly: brightness is only written when the state actually changes.
    func setDimmed(_ dimmed: Bool) {
        guard let screen else { return }
        if dimmed, savedLevel == nil {
            savedLevel = screen.brightness
            screen.brightness = Self.dimmedLevel
        } else if !dimmed, let saved = savedLevel {
            screen.brightness = saved
            savedLevel = nil
        }
    }
}
