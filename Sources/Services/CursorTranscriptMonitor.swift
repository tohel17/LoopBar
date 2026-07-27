import Foundation

/// Resolves Cursor composer transcripts once, then reads only bytes appended
/// since the previous refresh.
final class CursorTranscriptMonitor: @unchecked Sendable {
    enum TurnState: Sendable, Equatable {
        case none
        case running
        case completed
        case failed
    }

    struct Snapshot: Sendable {
        let modifiedAt: Date?
        let state: TurnState
    }

    private struct Entry {
        let url: URL
        var offset: UInt64
        var remainder: String
        var modifiedAt: Date?
        var state: TurnState
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func snapshots(
        for composerIDs: Set<String>,
        projectsURL: URL
    ) -> [String: Snapshot] {
        lock.lock()
        defer { lock.unlock() }

        entries = entries.filter {
            composerIDs.contains($0.key)
                && FileManager.default.fileExists(atPath: $0.value.url.path)
        }
        resolveMissingTranscripts(for: composerIDs, projectsURL: projectsURL)

        var result: [String: Snapshot] = [:]
        for composerID in composerIDs {
            guard var entry = entries[composerID] else { continue }
            update(&entry)
            entries[composerID] = entry
            result[composerID] = Snapshot(
                modifiedAt: entry.modifiedAt,
                state: entry.state
            )
        }
        return result
    }

    private func resolveMissingTranscripts(
        for composerIDs: Set<String>,
        projectsURL: URL
    ) {
        let missing = composerIDs.subtracting(entries.keys)
        guard !missing.isEmpty,
              let enumerator = FileManager.default.enumerator(
                at: projectsURL,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .isRegularFileKey,
                    .fileSizeKey
                ],
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        var candidates: [String: (url: URL, modifiedAt: Date)] = [:]
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            let composerID = fileURL.deletingPathExtension().lastPathComponent
            guard missing.contains(composerID) else { continue }
            let values = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            )
            guard values?.isRegularFile == true else { continue }
            let modifiedAt = values?.contentModificationDate ?? .distantPast
            if candidates[composerID] == nil
                || modifiedAt > candidates[composerID]!.modifiedAt {
                candidates[composerID] = (fileURL, modifiedAt)
            }
        }

        for (composerID, candidate) in candidates {
            entries[composerID] = Entry(
                url: candidate.url,
                offset: 0,
                remainder: "",
                modifiedAt: nil,
                state: .none
            )
        }
    }

    private func update(_ entry: inout Entry) {
        guard let values = try? entry.url.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else {
            return
        }

        let size = UInt64(max(values.fileSize ?? 0, 0))
        let modifiedAt = values.contentModificationDate
        guard modifiedAt != entry.modifiedAt || size != entry.offset else { return }

        if size < entry.offset {
            entry.offset = 0
            entry.remainder = ""
            entry.state = .none
        }

        guard let handle = try? FileHandle(forReadingFrom: entry.url) else { return }
        defer { try? handle.close() }

        // On first observation, a bounded tail is enough to recover the latest
        // turn boundary without loading an arbitrarily large conversation.
        if entry.offset == 0, size > 256 * 1_024 {
            entry.offset = size - 256 * 1_024
        }
        try? handle.seek(toOffset: entry.offset)
        guard let data = try? handle.readToEnd(),
              let appended = String(data: data, encoding: .utf8) else {
            return
        }

        let combined = entry.remainder + appended
        var lines = combined.components(separatedBy: "\n")
        if combined.hasSuffix("\n") {
            entry.remainder = ""
        } else {
            entry.remainder = lines.popLast() ?? ""
        }

        // Cursor does not always append an explicit turn_started record for a
        // follow-up in an existing composer, and completion may have come from
        // SQLite rather than the transcript. After the initial transcript read,
        // any later complete JSONL record is therefore live activity. A
        // turn_ended record in the same batch immediately replaces this
        // provisional running state below.
        // Only infer running from new content when the state is not already
        // terminal. Post-completion writes (metadata, summaries) should not
        // flip .completed/.failed back to .running; only an explicit
        // turn_started record (handled in apply()) may do that.
        if entry.modifiedAt != nil,
           entry.state != .completed, entry.state != .failed,
           lines.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            entry.state = .running
        }

        for line in lines {
            apply(line: line, to: &entry.state)
        }
        entry.offset = size
        entry.modifiedAt = modifiedAt
    }

    private func apply(line: String, to state: inout TurnState) {
        if line.contains("\"type\":\"turn_started\"") {
            state = .running
            return
        }
        guard line.contains("\"type\":\"turn_ended\"") else { return }
        if line.contains("\"status\":\"success\"") {
            state = .completed
        } else if line.contains("\"status\":\"error\"") {
            state = .failed
        } else {
            state = .none
        }
    }
}
