import Combine
import LimitNotchCore
import SwiftUI

/// Panel geometry plus the hover state that decides whether the notch is expanded.
@MainActor
final class NotchState: ObservableObject {
    /// Opens with a soft spring and a hint of overshoot; closes with a nearly critically damped
    /// one that has visually settled (under 0.1 pt off) by `collapseSettle`.
    static let expandAnimation = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let collapseAnimation = Animation.spring(response: 0.3, dampingFraction: 0.95)
    /// How long the collapse needs before the window can shrink back.
    static let collapseSettle: Duration = .milliseconds(450)
    /// A short dwell before opening, so sweeping the pointer across the menu bar does not expand it.
    static let hoverIntent: Duration = .milliseconds(100)
    /// Grace period before closing, so grazing the edge does not flicker.
    static let hoverGrace: Duration = .milliseconds(250)

    @Published private(set) var geometry: NotchGeometry
    @Published private(set) var isExpanded = false
    /// False while the display sleeps or the panel is hidden, so the mood glyph stops blinking.
    @Published var isAnimating = true

    /// Called with the new expansion state before SwiftUI animates it.
    var onExpansionChange: ((Bool) -> Void)?

    private var isHovered = false
    /// Keeps the notch open without a pointer (LIMITNOTCH_DEBUG_EXPANDED, for screenshots).
    private var isPinned = false
    private var pendingChange: Task<Void, Never>?

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    func update(geometry: NotchGeometry) {
        guard geometry != self.geometry else { return }
        self.geometry = geometry
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        updateExpansion()
    }

    func setHovered(_ hovered: Bool) {
        isHovered = hovered
        pendingChange?.cancel()
        let delay = hovered ? Self.hoverIntent : Self.hoverGrace
        pendingChange = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.updateExpansion()
        }
    }

    private func updateExpansion() {
        let expanded = isHovered || isPinned
        guard expanded != isExpanded else { return }
        // Grow the window first; the SwiftUI spring then animates inside it.
        onExpansionChange?(expanded)
        withAnimation(expanded ? Self.expandAnimation : Self.collapseAnimation) {
            isExpanded = expanded
        }
    }
}
