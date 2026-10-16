import Combine
import LimitNotchCore
import SwiftUI

/// Panel geometry plus the hover state that decides whether the notch is expanded.
@MainActor
final class NotchState: ObservableObject {
    static let expandAnimation = Animation.spring(response: 0.44, dampingFraction: 0.76)
    static let collapseAnimation = Animation.spring(response: 0.38, dampingFraction: 0.92)
    /// How long the collapse spring needs before the window can shrink back.
    static let collapseSettle: Duration = .milliseconds(480)
    /// A short dwell before opening, so sweeping the pointer across the menu bar does not expand it.
    static let hoverIntent: Duration = .milliseconds(90)
    /// Grace period before closing, so grazing the edge does not flicker.
    static let hoverGrace: Duration = .milliseconds(140)

    @Published private(set) var geometry: NotchGeometry
    @Published private(set) var isExpanded = false
    /// False while the display sleeps or the panel is hidden, so the mascot stops redrawing.
    @Published var isAnimating = true

    /// Called with the new expansion state before SwiftUI animates it.
    var onExpansionChange: ((Bool) -> Void)?

    private var isHovered = false
    private var pendingChange: Task<Void, Never>?

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    func update(geometry: NotchGeometry) {
        guard geometry != self.geometry else { return }
        self.geometry = geometry
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
        let expanded = isHovered
        guard expanded != isExpanded else { return }
        // Grow the window first; the SwiftUI spring then animates inside it.
        onExpansionChange?(expanded)
        withAnimation(expanded ? Self.expandAnimation : Self.collapseAnimation) {
            isExpanded = expanded
        }
    }
}
