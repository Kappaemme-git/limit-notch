import Combine
import Foundation
import LimitNotchCore

@MainActor
final class StatusStore: ObservableObject {
    @Published private(set) var snapshot: StatusSnapshot = .unavailable(nil)
    @Published private(set) var isExpanded = false

    var onExpansionChange: (() -> Void)?

    private let statusURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".usage-watcher/status.json")
    private var timer: Timer?
    private var isHovered = false
    private var isPinned = false
    private var suppressHoverUntilLeave = false

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        // Data(contentsOf:) only reads the watcher file. A missing or unreadable file is unavailable.
        snapshot = StatusSnapshot.from(data: try? Data(contentsOf: statusURL), at: Date())
    }

    func setHovered(_ hovered: Bool) {
        if hovered && !isHovered { refresh() }
        isHovered = hovered
        if !hovered { suppressHoverUntilLeave = false }
        updateExpansion()
    }

    func toggleExpanded() {
        refresh()
        if isExpanded {
            isPinned = false
            suppressHoverUntilLeave = true
        } else {
            isPinned = true
            suppressHoverUntilLeave = false
        }
        updateExpansion()
    }

    private func updateExpansion() {
        let expanded = isPinned || (isHovered && !suppressHoverUntilLeave)
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        onExpansionChange?()
    }
}
