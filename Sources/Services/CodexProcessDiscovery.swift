import Foundation

/// Discovers terminal-attached Codex CLI processes and maps them to rollout
/// transcripts. Process liveness answers whether a task is still alive; rollout
/// parsing remains responsible for the task's semantic state.
struct CodexProcessDiscovery {
    struct Snapshot: Sendable {
        let liveThreadIDs: Set<String>
        let liveRolloutPaths: Set<String>

        /// True only when every discovered Codex process was mapped to a
        /// rollout. When false, callers must retain their recency fallback for
        /// tasks not present in the live sets.
        let canDetermineAbsence: Bool

        static let unavailable = Snapshot(
            liveThreadIDs: [],
            liveRolloutPaths: [],
            canDetermineAbsence: false
        )

        func contains(threadID: String, rolloutPath: String) -> Bool {
            liveThreadIDs.contains(threadID)
                || (!rolloutPath.isEmpty && liveRolloutPaths.contains(rolloutPath))
        }
    }

    private struct Candidate {
        let pid: String
    }

    func snapshot() -> Snapshot {
        guard let processOutput = run(
            "/bin/ps",
            arguments: ["-Ao", "pid=,tty=,command="]
        ) else {
            return .unavailable
        }

        let candidates = processOutput
            .split(whereSeparator: \.isNewline)
            .compactMap(parseCandidate)

        // A successful process listing with no Codex CLI process is
        // authoritative: no terminal-attached Codex task is currently alive.
        guard !candidates.isEmpty else {
            return Snapshot(
                liveThreadIDs: [],
                liveRolloutPaths: [],
                canDetermineAbsence: true
            )
        }

        guard let lsofOutput = run(
            "/usr/sbin/lsof",
            arguments: ["-a", "-p", candidates.map(\.pid).joined(separator: ","), "-Fn"]
        ) else {
            return .unavailable
        }

        let filesByPID = lsofPathsByPID(lsofOutput)
        var rolloutPaths = Set<String>()
        var threadIDs = Set<String>()
        var mappedProcessCount = 0

        for candidate in candidates {
            guard let paths = filesByPID[candidate.pid],
                  let rolloutPath = newestRolloutPath(in: paths) else {
                continue
            }

            mappedProcessCount += 1
            rolloutPaths.insert(rolloutPath)

            if let metadata = transcriptMetadata(at: rolloutPath) {
                threadIDs.insert(metadata.id)
                if let parentID = metadata.parentID {
                    // Codex subagent rollouts point back to the parent thread.
                    // Including both IDs lets a root row inherit liveness when
                    // the shared process currently holds a child rollout open.
                    threadIDs.insert(parentID)
                }
            }
        }

        return Snapshot(
            liveThreadIDs: threadIDs,
            liveRolloutPaths: rolloutPaths,
            canDetermineAbsence: mappedProcessCount == candidates.count
        )
    }

    private func parseCandidate(_ line: Substring) -> Candidate? {
        let parts = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(maxSplits: 2, whereSeparator: \.isWhitespace)

        guard parts.count == 3 else { return nil }
        let pid = String(parts[0])
        let tty = String(parts[1])
        let command = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard tty != "??", isCodexCommand(command) else { return nil }
        return Candidate(pid: pid)
    }

    private func isCodexCommand(_ command: String) -> Bool {
        let lowered = command.lowercased()
        guard let executable = lowered.split(whereSeparator: \.isWhitespace).first else {
            return false
        }
        return executable == "codex"
            || executable.hasSuffix("/codex")
            || lowered.contains("/codex/codex")
    }

    private func lsofPathsByPID(_ output: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        var currentPID: String?

        for line in output.split(whereSeparator: \.isNewline) {
            guard let prefix = line.first else { continue }
            switch prefix {
            case "p":
                currentPID = String(line.dropFirst())
            case "n":
                guard let currentPID else { continue }
                result[currentPID, default: []].append(String(line.dropFirst()))
            default:
                continue
            }
        }
        return result
    }

    private func newestRolloutPath(in paths: [String]) -> String? {
        paths
            .filter {
                $0.contains("/.codex/sessions/")
                    && $0.hasSuffix(".jsonl")
            }
            .max {
                URL(fileURLWithPath: $0).lastPathComponent
                    < URL(fileURLWithPath: $1).lastPathComponent
            }
    }

    private func transcriptMetadata(at path: String) -> (id: String, parentID: String?)? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return nil
        }
        defer { try? handle.close() }

        let head = handle.readData(ofLength: 256 * 1_024)
        guard let firstLine = String(data: head, encoding: .utf8)?
            .split(whereSeparator: \.isNewline)
            .first,
              let object = try? JSONSerialization.jsonObject(with: Data(firstLine.utf8)) as? [String: Any],
              let payload = object["payload"] as? [String: Any],
              let id = payload["id"] as? String else {
            return nil
        }
        return (id, payload["parent_thread_id"] as? String)
    }

    private func run(_ executable: String, arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // Drain stdout before waiting so a large process listing cannot fill
        // the pipe buffer and deadlock the child process.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
