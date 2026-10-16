import Foundation

/// Reports changes to a few files in one directory as soon as the kernel sees them.
///
/// The helpers replace their files atomically (write a temporary file, then rename it over the
/// old one), which only shows up as a write to the directory; other writers may rewrite a file in
/// place. So the directory and each file are watched, and every source is re-armed after an event
/// because a replaced file is a new inode. Bursts are coalesced into one callback.
final class FileWatcher: @unchecked Sendable {
    private let directory: URL
    private let fileNames: [String]
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "dev.kappaemme.limitnotch.file-watcher")
    // Mutated only on `queue`.
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?

    /// Short enough to feel instant, long enough to merge a write and its rename.
    private static let coalesce: DispatchTimeInterval = .milliseconds(80)

    init(directory: URL, fileNames: [String], onChange: @escaping @Sendable () -> Void) {
        self.directory = directory
        self.fileNames = fileNames
        self.onChange = onChange
    }

    deinit {
        sources.forEach { $0.cancel() }
    }

    /// Starts watching; safe to call again, for example after the directory has been created.
    func start() {
        queue.async { self.arm() }
    }

    /// Arms the sources only if the directory could not be opened before.
    func ensureWatching() {
        queue.async { if self.sources.isEmpty { self.arm() } }
    }

    private func arm() {
        sources.forEach { $0.cancel() }
        sources = []
        guard let directorySource = watch(directory.path, events: .write) else { return }
        sources.append(directorySource)
        for name in fileNames {
            if let source = watch(directory.appendingPathComponent(name).path,
                                  events: [.write, .extend, .delete, .rename]) {
                sources.append(source)
            }
        }
    }

    private func watch(_ path: String, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: queue)
        source.setEventHandler { [weak self] in self?.changed() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.arm()
            self.onChange()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + Self.coalesce, execute: work)
    }
}
