import Combine
import Foundation
import LimitNotchCore

@MainActor
final class StatusStore: ObservableObject {
    @Published private(set) var snapshot: StatusSnapshot = .unavailable(nil)

    private static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".usage-watcher")
    private let statusURL = directory.appendingPathComponent("status.json")
    /// Written every ~60 s by claude_live.py; preferred when it holds newer Claude data.
    private let liveURL = directory.appendingPathComponent("claude_live.json")
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        // Data(contentsOf:) only reads the watcher files. A missing or unreadable file is unavailable.
        let next = StatusSnapshot.from(data: try? Data(contentsOf: statusURL),
                                       liveData: try? Data(contentsOf: liveURL), at: Date())
        if next != snapshot { snapshot = next }
    }
}
