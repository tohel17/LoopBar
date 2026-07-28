import Foundation

/// Reads local Claude Code sessions without changing Claude configuration,
/// transcripts, hooks, or terminal state.
///
/// Claude usually closes its transcript after appending to it, so file
/// timestamps alone cannot establish liveness. This service combines recent
/// JSONL metadata with Claude's live-session registry and terminal processes.
final class ClaudeAPI: @unchecked Sendable {
    private static let approvalSettleWindow: TimeInterval = 2
    private static let idleSettleWindow: TimeInterval = 3
    private static let busyWindow: TimeInterval = 30
    private static let recentWindow: TimeInterval = 6 * 60 * 60
    private let projectsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
    private let liveSessionsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/sessions")
    private var previousLiveIDs = Set<String>()
    private var missingPolls: [String: Int] = [:]
    private var claimedSessionByProcess: [String: String] = [:]

    func fetchAgents() async throws -> [CursorAgent] {
        try await Task.detached(priority: .userInitiated) {
            try self.readSessions(now: .now)
        }.value
    }

    private func readSessions(now: Date) throws -> [CursorAgent] {
        guard FileManager.default.fileExists(atPath: projectsURL.path) else { return [] }

        let processes = try discoverProcesses()
        let sessions = scanSessions(now: now, liveTranscriptPaths: Set(processes.compactMap(\.transcriptPath)))
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
                let liveProcess = processes.first { process in
                    process.transcriptPath == session.url.path
                        || claimedSessionByProcess[process.identity] == session.url.path
                }
                status = Self.liveStatus(
                    metadata: session.metadata,
                    process: liveProcess,
                    now: now
                )
                switch status {
                case .waitingForApproval:
                    detail = "Waiting for approval in Claude Code"
                case .waitingForInput:
                    detail = "Waiting for your response in Claude Code"
                case .completed:
                    detail = "Task finished · Claude Code is open"
                default:
                    let busy = now.timeIntervalSince(session.metadata.lastActivity ?? session.modifiedAt) < Self.busyWindow
                    detail = busy ? "Working in Claude Code" : "Claude Code is open"
                }
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

    private func scanSessions(now: Date, liveTranscriptPaths: Set<String>) -> [Session] {
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
                      now.timeIntervalSince(modified) < Self.recentWindow || liveTranscriptPaths.contains(file.path)
                else { return nil }
                return Session(url: file, projectURL: project, modifiedAt: modified, metadata: transcriptMetadata(at: file))
            }
        }
    }

    private func claimsByProject(for processes: [ClaudeProcess], sessions: [Session]) -> [String: Set<String>] {
        var claims: [String: Set<String>] = [:]
        let liveProcesses = Set(processes.map(\.identity))
        claimedSessionByProcess = claimedSessionByProcess.filter { liveProcesses.contains($0.key) }

        for process in processes.sorted(by: { $0.identity < $1.identity }) {
            let project = process.transcriptPath
                .map { URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent }
                ?? Self.encodedProjectPath(process.cwd.path)
            let candidates = sessions
                .filter { $0.projectURL.lastPathComponent == project }
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .map(\.url.path)
            guard !candidates.isEmpty else { continue }

            let alreadyClaimed = Set(claims[project, default: []])
            let exact = process.transcriptPath.flatMap { candidates.contains($0) ? $0 : nil }
            let stable = claimedSessionByProcess[process.identity]
            let sessionPath = exact
                ?? (stable.flatMap { candidates.contains($0) ? $0 : nil })
                ?? candidates.first(where: { !alreadyClaimed.contains($0) })
                ?? candidates[0]
            claimedSessionByProcess[process.identity] = sessionPath
            claims[project, default: []].insert(sessionPath)
        }
        return claims
    }

    private func discoverProcesses() throws -> [ClaudeProcess] {
        let ps = try run("/bin/ps", arguments: ["-Ao", "pid=,ppid=,tty=,command="])
        let rows = Self.processRows(from: ps)
        let claudeRows = Dictionary(
            uniqueKeysWithValues: rows.filter { Self.isClaudeCommand($0.command) }.map { ($0.pid, $0) }
        )

        var processes = registeredProcesses(liveRows: claudeRows, allRows: rows)
        let registeredPIDs = Set(processes.map(\.pid))
        let terminalCandidates = claudeRows.values.filter { $0.tty != "??" && !registeredPIDs.contains($0.pid) }
        let unique = Dictionary(terminalCandidates.map { ($0.tty, $0.pid) }, uniquingKeysWith: { first, _ in first })
        let cwdByPID = lsofCWDs(for: Array(unique.values).map(String.init))
        processes += unique.compactMap { tty, pid in
            guard let cwd = cwdByPID[String(pid)] else { return nil }
            return ClaudeProcess(
                pid: pid,
                identity: "tty:\(tty)",
                tty: tty,
                cwd: URL(fileURLWithPath: cwd),
                transcriptPath: nil,
                permissionMode: Self.permissionMode(in: claudeRows[pid]?.command ?? ""),
                hasRunningDescendant: Self.hasDescendant(of: pid, in: rows)
            )
        }
        return processes
    }

    private func registeredProcesses(
        liveRows: [Int: ProcessRow],
        allRows: [ProcessRow]
    ) -> [ClaudeProcess] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: liveSessionsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files.compactMap { file in
            guard file.pathExtension == "json",
                  let data = try? Data(contentsOf: file),
                  let record = try? JSONDecoder().decode(LiveSessionRecord.self, from: data),
                  let row = liveRows[record.pid]
            else { return nil }

            let transcript = transcriptURL(sessionID: record.sessionId, cwd: record.cwd)
            return ClaudeProcess(
                pid: record.pid,
                identity: "pid:\(record.pid)",
                tty: row.tty,
                cwd: URL(fileURLWithPath: record.cwd),
                transcriptPath: transcript.path,
                permissionMode: Self.permissionMode(in: row.command),
                hasRunningDescendant: Self.hasDescendant(of: record.pid, in: allRows)
            )
        }
    }

    private func transcriptURL(sessionID: String, cwd: String) -> URL {
        let expected = projectsURL
            .appendingPathComponent(Self.encodedProjectPath(cwd), isDirectory: true)
            .appendingPathComponent(sessionID)
            .appendingPathExtension("jsonl")
        if FileManager.default.fileExists(atPath: expected.path) { return expected }

        if let projects = try? FileManager.default.contentsOfDirectory(
            at: projectsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ), let match = projects.lazy
            .map({ $0.appendingPathComponent(sessionID).appendingPathExtension("jsonl") })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return match
        }
        return expected
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
        let readLength = min(size, 512 * 1_024)
        try? handle.seek(toOffset: size - readLength)
        guard let data = try? handle.readToEnd(),
              let transcriptText = String(data: data, encoding: .utf8) else { return .empty }
        return Self.transcriptMetadata(from: transcriptText)
    }

    static func transcriptMetadata(from transcriptText: String) -> TranscriptMetadata {
        let objects = transcriptText.split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        var metadata = TranscriptMetadata.empty
        var pendingTools: [String: PendingTool] = [:]

        for object in objects {
            let type = object["type"] as? String
            let timestamp = date(in: object)
            if type == "assistant", let blocks = contentBlocks(in: object) {
                for block in blocks where block["type"] as? String == "tool_use" {
                    guard let id = block["id"] as? String, let name = block["name"] as? String else { continue }
                    pendingTools[id] = PendingTool(id: id, name: name, requestedAt: timestamp)
                }
            }
            if type == "user", let blocks = contentBlocks(in: object) {
                for block in blocks where block["type"] as? String == "tool_result" {
                    if let id = block["tool_use_id"] as? String { pendingTools.removeValue(forKey: id) }
                }
            }
            if type == "error" { metadata.hasError = true }
        }

        for object in objects.reversed() {
            if metadata.model.isEmpty { metadata.model = string(in: object, key: "model") ?? "" }
            let type = object["type"] as? String
            if type == "user" || type == "assistant" {
                if metadata.lastRole.isEmpty { metadata.lastRole = type ?? "" }
                if metadata.lastActivity == nil { metadata.lastActivity = date(in: object) }
            }
            if metadata.prompt.isEmpty, type == "user" { metadata.prompt = clean(text(in: object)) }
            if !metadata.prompt.isEmpty, !metadata.model.isEmpty, metadata.lastActivity != nil { break }
        }
        metadata.pendingTools = Array(pendingTools.values)
        return metadata
    }

    private static func contentBlocks(in object: [String: Any]) -> [[String: Any]]? {
        (object["message"] as? [String: Any])?["content"] as? [[String: Any]]
    }

    private static func text(in object: [String: Any]) -> String {
        guard let message = object["message"] as? [String: Any] else { return "" }
        if let content = message["content"] as? String { return content }
        if let blocks = message["content"] as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
        }
        return ""
    }

    private static func string(in object: [String: Any], key: String) -> String? {
        if let value = object[key] as? String { return value }
        if let message = object["message"] as? [String: Any] { return message[key] as? String }
        return nil
    }

    private static func date(in object: [String: Any]) -> Date? {
        guard let timestamp = object["timestamp"] as? String else { return nil }
        return ISO8601DateFormatter().date(from: timestamp)
            ?? ISO8601DateFormatter.withFractionalSeconds.date(from: timestamp)
    }

    private static func clean(_ value: String) -> String {
        let trimmed = value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("<"), !trimmed.hasPrefix("{") else { return "" }
        return trimmed
    }

    private func displayTitle(_ value: String) -> String {
        value.count > 72 ? String(value.prefix(69)) + "..." : value
    }

    /// `ps` joins argv with single spaces, so an executable path that contains
    /// spaces arrives split across tokens. The desktop build lives under
    /// "Application Support", so matching only the first token misses every
    /// Claude Code session launched from the app. Re-join the leading tokens
    /// that can only be fragments of that path: an absolute or flag-like token
    /// starts the next argument.
    static func isClaudeCommand(_ command: String) -> Bool {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = tokens.first else { return false }

        var executable = first
        var candidates = [first]
        for token in tokens.dropFirst() {
            guard first.hasPrefix("/"), !token.hasPrefix("/"), !token.hasPrefix("-") else { break }
            executable += " " + token
            candidates.append(executable)
        }
        return candidates.contains { candidate in
            let value = candidate.lowercased()
            return value == "claude" || value.hasSuffix("/claude")
        }
    }

    static func liveStatus(
        metadata: TranscriptMetadata,
        process: ClaudeProcess?,
        now: Date
    ) -> AgentStatus {
        let pending = metadata.pendingTools.sorted {
            ($0.requestedAt ?? .distantPast) > ($1.requestedAt ?? .distantPast)
        }
        if pending.contains(where: { $0.name == "AskUserQuestion" }) {
            return .waitingForInput
        }

        guard process?.hasRunningDescendant != true else { return .running }
        let mode = process?.permissionMode ?? "default"
        let approvalTool = pending.first { tool in
            switch tool.name {
            case "Bash", "ExitPlanMode":
                return true
            case "Edit", "Write", "NotebookEdit":
                return mode != "acceptEdits" && mode != "bypassPermissions" && mode != "dontAsk"
            default:
                return false
            }
        }
        if let approvalTool,
           let requestedAt = approvalTool.requestedAt,
           now.timeIntervalSince(requestedAt) >= approvalSettleWindow {
            return .waitingForApproval
        }

        // Nothing is pending and no tool is executing. A transcript that ends on
        // a settled assistant message means the turn is over and the process is
        // just an open prompt — keeping it "running" is why finished work never
        // cleared. A trailing user entry still means the model is generating, so
        // only assistant endings settle, and only after the write goes quiet.
        if pending.isEmpty,
           metadata.lastRole == "assistant",
           let lastActivity = metadata.lastActivity,
           now.timeIntervalSince(lastActivity) >= idleSettleWindow {
            return .completed
        }
        return .running
    }

    static func processRows(from output: String) -> [ProcessRow] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(maxSplits: 3, whereSeparator: \.isWhitespace)
            guard fields.count == 4,
                  let pid = Int(fields[0]),
                  let parentPID = Int(fields[1])
            else { return nil }
            return ProcessRow(pid: pid, parentPID: parentPID, tty: String(fields[2]), command: String(fields[3]))
        }
    }

    static func encodedProjectPath(_ path: String) -> String {
        String(path.map { character in
            character.isLetter || character.isNumber ? character : "-"
        })
    }

    private static func permissionMode(in command: String) -> String {
        let fields = command.split(whereSeparator: \.isWhitespace).map(String.init)
        if let field = fields.first(where: { $0.hasPrefix("--permission-mode=") }) {
            return String(field.dropFirst("--permission-mode=".count))
        }
        guard let index = fields.firstIndex(of: "--permission-mode"), fields.indices.contains(index + 1) else {
            return "default"
        }
        return fields[index + 1]
    }

    private static func hasDescendant(of pid: Int, in rows: [ProcessRow]) -> Bool {
        rows.contains { $0.parentPID == pid }
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

struct ClaudeProcess {
    let pid: Int
    let identity: String
    let tty: String
    let cwd: URL
    let transcriptPath: String?
    let permissionMode: String
    let hasRunningDescendant: Bool
}

struct ProcessRow {
    let pid: Int
    let parentPID: Int
    let tty: String
    let command: String
}

private struct LiveSessionRecord: Decodable {
    let pid: Int
    let sessionId: String
    let cwd: String
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

struct TranscriptMetadata {
    var prompt: String
    var model: String
    var lastActivity: Date?
    /// `type` of the transcript's final conversational entry. "assistant" means
    /// the turn ended; "user" means the model is still producing a reply.
    var lastRole: String
    var hasError: Bool
    var pendingTools: [PendingTool]
    static let empty = TranscriptMetadata(
        prompt: "",
        model: "",
        lastActivity: nil,
        lastRole: "",
        hasError: false,
        pendingTools: []
    )
}

struct PendingTool {
    let id: String
    let name: String
    let requestedAt: Date?
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
