import Combine
import LimitNotchCore
import SwiftUI

/// Panel geometry plus the hover/click state that decides whether the notch is expanded.
@MainActor
final class NotchState: ObservableObject {
    static let expandAnimation = Animation.spring(response: 0.42, dampingFraction: 0.72)
    static let collapseAnimation = Animation.spring(response: 0.36, dampingFraction: 0.9)
    /// How long the collapse spring needs before the window can shrink back.
    static let collapseSettle: Duration = .milliseconds(450)

    @Published private(set) var geometry: NotchGeometry
    @Published private(set) var isExpanded = false
    /// False while the display sleeps or the panel is hidden, so the mascot stops redrawing.
    @Published var isAnimating = true

    /// Called with the new expansion state before SwiftUI animates it.
    var onExpansionChange: ((Bool) -> Void)?

    private var isHovered = false
    private var isPinned = false
    private var suppressHoverUntilLeave = false
    private var pendingCollapse: Task<Void, Never>?

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    func update(geometry: NotchGeometry) {
        guard geometry != self.geometry else { return }
        self.geometry = geometry
    }

    func setHovered(_ hovered: Bool) {
        isHovered = hovered
        if !hovered { suppressHoverUntilLeave = false }
        pendingCollapse?.cancel()
        if hovered {
            updateExpansion()
        } else {
            // A short grace period keeps the panel from flickering when the pointer grazes the edge.
            pendingCollapse = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                self?.updateExpansion()
            }
        }
    }

    func toggleExpanded() {
        if isExpanded {
            isPinned = false
            suppressHoverUntilLeave = true
        } else {
            isPinned = true
            suppressHoverUntilLeave = false
        }
        updateExpansion()
    }

    /// Closes a panel opened by a click, for example when the user clicks elsewhere.
    func dismissPin() {
        guard isPinned else { return }
        isPinned = false
        updateExpansion()
    }

    private func updateExpansion() {
        let expanded = isPinned || (isHovered && !suppressHoverUntilLeave)
        guard expanded != isExpanded else { return }
        // Grow the window first; the SwiftUI spring then animates inside it.
        onExpansionChange?(expanded)
        withAnimation(expanded ? Self.expandAnimation : Self.collapseAnimation) {
            isExpanded = expanded
        }
    }
}
