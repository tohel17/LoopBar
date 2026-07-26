import Foundation

/// Reads local Claude Code sessions without changing Claude configuration,
/// transcripts, hooks, or terminal state.
///
/// Claude usually closes its transcript after appending to it, so file
/// timestamps alone cannot establish liveness. This service combines recent
/// JSONL metadata with terminal-attached `claude` processes and their CWDs.
final class ClaudeAPI: @unchecked Sendable {
    private static let busyWindow: TimeInterval = 30
    private static let recentWindow: TimeInterval = 6 * 60 * 60
    private let projectsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
    private var previousLiveIDs = Set<String>()
    private var missingPolls: [String: Int] = [:]
    private var claimedSessionByTTY: [String: String] = [:]

    func fetchAgents() async throws -> [CursorAgent] {
        try await Task.detached(priority: .userInitiated) {
            try self.readSessions(now: .now)
        }.value
    }

    private func readSessions(now: Date) throws -> [CursorAgent] {
        guard FileManager.default.fileExists(atPath: projectsURL.path) else { return [] }

        let processes = try discoverProcesses()
        let sessions = scanSessions(now: now)
        var claims = claimsByProject(for: processes, sessions: sessions)
        var liveIDs = Set<String>()

        let agents = sessions.compactMap { session -> CursorAgent? in
            let projectKey = session.projectURL.lastPathComponent
            let isLive = claims[projectKey]?.remove(session.url.path) != nil
            if isLive { liveIDs.insert(session.url.path) }

            let priorLive = previousLiveIDs.contains(session.url.path) || missingPolls[session.url.path] != nil
            let missingCount: Int
            if isLive {
                missingPolls.removeValue(forKey: session.url.path)
                missingCount = 0
            } else if priorLive {
                missingCount = (missingPolls[session.url.path] ?? 0) + 1
                missingPolls[session.url.path] = missingCount
            } else {
                missingCount = 0
            }

            let status: AgentStatus
            let detail: String
            if isLive {
                let busy = now.timeIntervalSince(session.metadata.lastActivity ?? session.modifiedAt) < Self.busyWindow
                status = .running
                detail = busy ? "Working in Claude Code" : "Claude Code is open · waiting"
            } else if priorLive, missingCount >= 2 {
                status = session.metadata.hasError ? .failed : .completed
                detail = status == .failed ? "Claude Code stopped with an error" : "Claude Code session finished"
            } else if priorLive {
                status = .running
                detail = "Checking whether Claude Code is still open"
            } else {
                status = session.metadata.hasError ? .failed : .unknown
                detail = "Last activity in Claude Code"
            }

            let title = session.metadata.prompt.isEmpty ? session.projectName : session.metadata.prompt
            let model = session.metadata.model.isEmpty ? "Claude Code" : session.metadata.model
            return CursorAgent(
                id: "claude-\(session.url.lastPathComponent)",
                source: .claude,
                title: displayTitle(title),
                status: status,
                progress: nil,
                latestStatus: "\(detail) · \(model) · \(session.projectName)",
                updatedAt: session.metadata.lastActivity ?? session.modifiedAt,
                url: session.projectURL
            )
        }

        missingPolls = missingPolls.filter { liveIDs.contains($0.key) || $0.value < 2 }
        previousLiveIDs = liveIDs.union(missingPolls.keys)
        return agents
            .filter { $0.status != .unknown || now.timeIntervalSince($0.updatedAt ?? .distantPast) < Self.recentWindow }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            .prefix(3)
            .map { $0 }
    }

    private func scanSessions(now: Date) -> [Session] {
        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: projectsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return projects.flatMap { project -> [Session] in
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: project,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            return files.compactMap { file -> Session? in
                guard file.pathExtension == "jsonl",
                      let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      now.timeIntervalSince(modified) < Self.recentWindow else { return nil }
                return Session(url: file, projectURL: project, modifiedAt: modified, metadata: transcriptMetadata(at: file))
            }
        }
    }

    private func claimsByProject(for processes: [ClaudeProcess], sessions: [Session]) -> [String: Set<String>] {
        var claims: [String: Set<String>] = [:]
        let liveTTYs = Set(processes.map(\.tty))
        claimedSessionByTTY = claimedSessionByTTY.filter { liveTTYs.contains($0.key) }

        for process in processes.sorted(by: { $0.tty < $1.tty }) {
            let project = process.cwd.path.replacingOccurrences(of: "/", with: "-")
            let candidates = sessions
                .filter { $0.projectURL.lastPathComponent == project }
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .map(\.url.path)
            guard !candidates.isEmpty else { continue }

            let alreadyClaimed = Set(claims[project, default: []])
            let stable = claimedSessionByTTY[process.tty]
            let sessionPath = (stable.flatMap { candidates.contains($0) ? $0 : nil })
                ?? candidates.first(where: { !alreadyClaimed.contains($0) })
                ?? candidates[0]
            claimedSessionByTTY[process.tty] = sessionPath
            claims[project, default: []].insert(sessionPath)
        }
        return claims
    }

    private func discoverProcesses() throws -> [ClaudeProcess] {
        let ps = try run("/bin/ps", arguments: ["-Ao", "pid=,tty=,command="])
        let candidates = ps.split(whereSeparator: \.isNewline).compactMap { line -> (String, String)? in
            let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard fields.count == 3, fields[1] != "??", isClaudeCommand(String(fields[2])) else { return nil }
            return (String(fields[0]), String(fields[1]))
        }
        let unique = Dictionary(candidates.map { ($0.1, $0.0) }, uniquingKeysWith: { first, _ in first })
        let cwdByPID = lsofCWDs(for: Array(unique.values))
        return unique.compactMap { tty, pid in
            guard let cwd = cwdByPID[pid] else { return nil }
            return ClaudeProcess(tty: tty, cwd: URL(fileURLWithPath: cwd), transcriptPath: nil)
        }
    }

    private func lsofCWDs(for pids: [String]) -> [String: String] {
        guard !pids.isEmpty,
              let output = try? run("/usr/sbin/lsof", arguments: ["-a", "-p", pids.joined(separator: ","), "-Fn"]) else { return [:] }
        var result: [String: String] = [:]
        var currentPID: String?
        var expectsCWD = false
        for line in output.split(whereSeparator: \.isNewline) {
            guard let prefix = line.first else { continue }
            let value = String(line.dropFirst())
            if prefix == "p" { currentPID = value; expectsCWD = false }
            if prefix == "f" { expectsCWD = value == "cwd" }
            if prefix == "n", expectsCWD, let currentPID, value.hasPrefix("/") {
                result[currentPID] = value
                expectsCWD = false
            }
        }
        return result
    }

    private func transcriptMetadata(at url: URL) -> TranscriptMetadata {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .empty }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let readLength = min(size, 128 * 1_024)
        try? handle.seek(toOffset: size - readLength)
        guard let data = try? handle.readToEnd(),
              let transcriptText = String(data: data, encoding: .utf8) else { return .empty }
        var metadata = TranscriptMetadata.empty
        for line in transcriptText.split(separator: "\n").reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if metadata.model.isEmpty { metadata.model = string(in: object, key: "model") ?? "" }
            let type = object["type"] as? String
            if metadata.lastActivity == nil, type == "user" || type == "assistant" {
                metadata.lastActivity = date(in: object)
            }
            if metadata.prompt.isEmpty, type == "user" { metadata.prompt = clean(text(in: object)) }
            if type == "error" { metadata.hasError = true }
            if !metadata.prompt.isEmpty, !metadata.model.isEmpty, metadata.lastActivity != nil { break }
        }
        return metadata
    }

    private func text(in object: [String: Any]) -> String {
        guard let message = object["message"] as? [String: Any] else { return "" }
        if let content = message["content"] as? String { return content }
        if let blocks = message["content"] as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
        }
        return ""
    }

    private func string(in object: [String: Any], key: String) -> String? {
        if let value = object[key] as? String { return value }
        if let message = object["message"] as? [String: Any] { return message[key] as? String }
        return nil
    }

    private func date(in object: [String: Any]) -> Date? {
        guard let timestamp = object["timestamp"] as? String else { return nil }
        return ISO8601DateFormatter().date(from: timestamp)
            ?? ISO8601DateFormatter.withFractionalSeconds.date(from: timestamp)
    }

    private func clean(_ value: String) -> String {
        let trimmed = value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("<"), !trimmed.hasPrefix("{") else { return "" }
        return trimmed
    }

    private func displayTitle(_ value: String) -> String {
        value.count > 72 ? String(value.prefix(69)) + "..." : value
    }

    private func isClaudeCommand(_ command: String) -> Bool {
        guard let executable = command.split(separator: " ").first?.lowercased() else { return false }
        return executable == "claude" || executable.hasSuffix("/claude")
    }

    private func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Drain stdout before waiting. Otherwise a verbose `ps`/`lsof` result
        // can fill the pipe buffer and leave the initial refresh stuck forever.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ClaudeError.processUnavailable }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct ClaudeProcess {
    let tty: String
    let cwd: URL
    let transcriptPath: String?
}

private enum ClaudeError: LocalizedError {
    case processUnavailable

    var errorDescription: String? {
        "Claude process discovery was unavailable."
    }
}

private struct Session {
    let url: URL
    let projectURL: URL
    let modifiedAt: Date
    let metadata: TranscriptMetadata
    var projectName: String { projectURL.lastPathComponent.replacingOccurrences(of: "-", with: "/") }
}

private struct TranscriptMetadata {
    var prompt: String
    var model: String
    var lastActivity: Date?
    var hasError: Bool
    static let empty = TranscriptMetadata(prompt: "", model: "", lastActivity: nil, hasError: false)
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
