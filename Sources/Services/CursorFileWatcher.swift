import CoreServices
import Foundation

/// Watches Cursor's local state directories and coalesces bursts of filesystem
/// writes into one refresh request.
final class CursorFileWatcher {
    private let queue = DispatchQueue(label: "loopbar.cursor-file-events", qos: .utility)
    private var stream: FSEventStreamRef?
    private var pendingChange: DispatchWorkItem?
    private var onChange: (() -> Void)?

    func start(onChange: @escaping () -> Void) {
        stop()
        self.onChange = onChange

        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage").path,
            home.appendingPathComponent(".cursor").path
        ]
        let paths = candidates.filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, contextInfo, _, _, _, _ in
            guard let contextInfo else { return }
            let watcher = Unmanaged<CursorFileWatcher>
                .fromOpaque(contextInfo)
                .takeUnretainedValue()
            watcher.scheduleChange()
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
        )

        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.15,
            flags
        ) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        pendingChange?.cancel()
        pendingChange = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        onChange = nil
    }

    private func scheduleChange() {
        pendingChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        pendingChange = work
        queue.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    deinit {
        stop()
    }
}
