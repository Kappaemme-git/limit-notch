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
    private var refreshTask: Task<Void, Never>?
    private var refreshSerial = 0

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        refreshTask?.cancel()
        refreshSerial += 1
        let serial = refreshSerial
        let statusURL = self.statusURL
        let liveURL = self.liveURL
        refreshTask = Task.detached(priority: .utility) { [weak self] in
            let next = StatusSnapshot.from(data: try? Data(contentsOf: statusURL),
                                           liveData: try? Data(contentsOf: liveURL), at: Date())
            await MainActor.run {
                guard let self, self.refreshSerial == serial else { return }
                if next != self.snapshot { self.snapshot = next }
            }
        }
    }
}
