import Combine
import Foundation
import LimitNotchCore

@MainActor
final class StatusStore: ObservableObject {
    @Published private(set) var snapshot: StatusSnapshot = .unavailable(nil)

    private let statusURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".usage-watcher/status.json")
    private var timer: Timer?

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
}
