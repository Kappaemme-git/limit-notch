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
    /// Set with LIMITNOTCH_DEBUG_MOOD to show fixed design values instead of the real files.
    private let debugScenario = DebugScenario(environment: ProcessInfo.processInfo.environment)
    private var watcher: FileWatcher?
    private var clock: Timer?
    private var refreshTask: Task<Void, Never>?
    private var refreshSerial = 0

    func start() {
        refresh()
        guard debugScenario == nil else { return }
        let watcher = FileWatcher(directory: Self.directory,
                                  fileNames: [statusURL.lastPathComponent, liveURL.lastPathComponent]) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        watcher.start()
        self.watcher = watcher
        // Files are read when they change. This slow tick only lets data age into "stale" when
        // the helpers stop writing, and picks up the directory if it did not exist yet.
        clock = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.watcher?.ensureWatching()
                self?.refresh()
            }
        }
    }

    func refresh() {
        if let debugScenario {
            snapshot = debugScenario.snapshot(at: Date())
            return
        }
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
