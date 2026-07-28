import Foundation

/// Reads recent local Codex threads without modifying Codex state.
struct CodexAPI {
    private let databaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/state_5.sqlite")
    private let processDiscovery = CodexProcessDiscovery()

    func fetchAgents() async throws -> [CursorAgent] {
        try await Task.detached(priority: .userInitiated) {
            let liveness = self.processDiscovery.snapshot()
            return try self.readThreads(from: self.databaseURL, liveness: liveness)
        }.value
    }

    private func readThreads(
        from databaseURL: URL,
        liveness: CodexProcessDiscovery.Snapshot
    ) throws -> [CursorAgent] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return []
        }

        let query = """
            SELECT
                id,
                SUBSTR(COALESCE(NULLIF(title, ''), NULLIF(preview, ''), 'Untitled Codex task'), 1, 160) AS title,
                SUBSTR(COALESCE(NULLIF(preview, ''), NULLIF(first_user_message, ''), ''), 1, 240) AS preview,
                COALESCE(NULLIF(agent_nickname, ''), NULLIF(model, ''), NULLIF(model_provider, ''), 'Codex') AS detail,
                COALESCE(NULLIF(cwd, ''), '') AS cwd,
                COALESCE(NULLIF(git_branch, ''), '') AS git_branch,
                COALESCE(source, '') AS source,
                rollout_path,
                COALESCE(NULLIF(recency_at_ms, 0), NULLIF(updated_at_ms, 0), updated_at * 1000) AS updated_at_ms
            FROM threads
            WHERE archived = 0 AND source NOT LIKE '%subagent%'
            ORDER BY updated_at_ms DESC
            LIMIT 3;
            """

        let result = try SQLiteJSONQuery.run(
            database: databaseURL,
            query: query,
            busyTimeoutMS: 1000
        )
        guard result.status == 0 else {
            throw APIError.localCodexUnavailable(result.stderr)
        }

        let now = Date()
        let threads = try SQLiteJSONQuery.decodeRows([LocalThread].self, from: result.stdout)
        return threads.map { thread in
            let updatedAt = Date(timeIntervalSince1970: thread.updatedAtMilliseconds / 1_000)
            let isRecentlyActive = now.timeIntervalSince(updatedAt) < 120
            let status = Self.status(
                for: thread,
                isProcessLive: liveness.contains(
                    threadID: thread.id,
                    rolloutPath: thread.rolloutPath
                ),
                canDetermineProcessAbsence: liveness.canDetermineAbsence
                    && thread.isTerminalSource,
                isRecentlyActive: isRecentlyActive
            )
            return CursorAgent(
                id: "codex-\(thread.id)",
                source: .codex,
                title: Self.displayTitle(from: thread.title),
                status: status,
                progress: nil,
                latestStatus: Self.statusText(for: thread, status: status, updatedAt: updatedAt),
                updatedAt: updatedAt,
                url: Self.codexThreadURL(threadId: thread.id)
            )
        }
    }

    private static func codexThreadURL(threadId: String) -> URL? {
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/\(threadId)"
        return components.url
    }

    private static func displayTitle(from title: String) -> String {
        let singleLine = title
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? title
        let trimmed = singleLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled Codex task" }

        if trimmed.count > 72 {
            return "\(trimmed.prefix(69))..."
        }
        return trimmed
    }

    private static func status(
        for thread: LocalThread,
        isProcessLive: Bool,
        canDetermineProcessAbsence: Bool,
        isRecentlyActive: Bool
    ) -> AgentStatus {
        let tail = rolloutTail(at: thread.rolloutPath)
        let semanticStatus = status(fromRollout: tail, isRecentlyUpdated: false)

        if isProcessLive {
            return semanticStatus == .unknown ? .running : semanticStatus
        }
        if semanticStatus == .completed {
            return .completed
        }
        if canDetermineProcessAbsence {
            return .unknown
        }
        if semanticStatus.needsAttention {
            return semanticStatus
        }
        return isRecentlyActive ? .running : .unknown
    }

    /// Derives task state from explicit rollout lifecycle records. Database
    /// recency is only a legacy fallback: hybrid Codex updates thread metadata
    /// for background activity that does not mean an agent is running.
    static func status(fromRollout tail: String, isRecentlyUpdated: Bool) -> AgentStatus {
        let lastTaskStarted = latestIndex(of: "\"type\":\"task_started\"", in: tail) ?? -1
        let lastTaskComplete = latestIndex(of: "\"type\":\"task_complete\"", in: tail) ?? -1
        // Approval records can remain in the rollout after the agent resumes.
        // Treat later reasoning/messages/tool output as a newer checkpoint so
        // a stale approval cannot mask active work as "Needs approval".
        let lastActivity = [
            "\"type\":\"function_call\"",
            "\"type\":\"function_call_output\"",
            "\"type\":\"custom_tool_call\"",
            "\"type\":\"custom_tool_call_output\"",
            "\"type\":\"agent_message\"",
            "\"type\":\"agent_reasoning\"",
            "\"type\":\"reasoning\""
        ].compactMap { latestIndex(of: $0, in: tail) }.max() ?? -1
        let checkpoint = max(lastTaskStarted, lastTaskComplete, lastActivity)
        let lastApproval = [
            "\"type\":\"execCommandApproval\"",
            "\"type\":\"applyPatchApproval\"",
            "\"type\":\"permissions_request_approval\"",
            "\"type\":\"command_execution_request_approval\"",
            "\"type\":\"file_change_request_approval\""
        ].compactMap { latestIndex(of: $0, in: tail) }.max() ?? -1
        let lastUserInput = [
            "has_pending_input=true",
            "\"type\":\"tool_request_user_input\"",
            "\"type\":\"request_user_input\""
        ].compactMap { latestIndex(of: $0, in: tail) }.max() ?? -1
        let lastBlocked = [
            "\"status\":\"blocked\"",
            "\"type\":\"goal_updated\",\"status\":\"blocked\""
        ].compactMap { latestIndex(of: $0, in: tail) }.max() ?? -1
        if lastApproval > checkpoint {
            return .waitingForApproval
        }
        if lastUserInput > checkpoint {
            return .waitingForInput
        }
        if lastBlocked > checkpoint {
            return .blocked
        }
        if lastTaskComplete > lastTaskStarted {
            return .completed
        }
        if lastTaskStarted >= 0 {
            return .running
        }
        return isRecentlyUpdated ? .running : .unknown
    }

    private static func statusText(for thread: LocalThread, status: AgentStatus, updatedAt: Date) -> String {
        let detail = thread.detail.isEmpty ? "Codex" : thread.detail
        let branch = thread.gitBranch.isEmpty ? "" : " · \(thread.gitBranch)"
        let location = URL(fileURLWithPath: thread.cwd).lastPathComponent
        let cwdLabel = location.isEmpty ? "" : " · \(location)"

        switch status {
        case .waitingForApproval:
            return "Waiting for approval · \(detail)\(branch)\(cwdLabel)"
        case .waitingForInput:
            return "Waiting for your response · \(detail)\(branch)\(cwdLabel)"
        case .blocked:
            return "Blocked · \(detail)\(branch)\(cwdLabel)"
        case .completed:
            return "Completed \(updatedAt.formatted(.relative(presentation: .named))) · \(detail)\(branch)\(cwdLabel)"
        case .running:
            return "Active in \(detail)\(branch)\(cwdLabel)"
        default:
            return "Last active \(updatedAt.formatted(.relative(presentation: .named))) · \(detail)\(branch)\(cwdLabel)"
        }
    }

    private static func rolloutTail(at path: String) -> String {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            return ""
        }
        do {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer { try? handle.close() }
            let fileSize = try handle.seekToEnd()
            // Long hybrid turns can exceed the old 96 KiB window before the
            // next poll. Retain enough history to keep the task_started marker.
            let tailSize: UInt64 = 1_024 * 1_024
            try handle.seek(toOffset: fileSize > tailSize ? fileSize - tailSize : 0)
            return String(data: handle.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private static func latestIndex(of needle: String, in haystack: String) -> Int? {
        guard let range = haystack.range(of: needle, options: [.caseInsensitive, .backwards]) else {
            return nil
        }
        return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
    }

    private struct LocalThread: Decodable {
        let id: String
        let title: String
        let preview: String
        let detail: String
        let cwd: String
        let gitBranch: String
        let source: String
        let rolloutPath: String
        let updatedAtMilliseconds: Double

        var isTerminalSource: Bool {
            let normalized = source.lowercased()
            return normalized.contains("cli") || normalized.contains("terminal")
        }

        enum CodingKeys: String, CodingKey {
            case id, title, preview, detail, cwd, source
            case gitBranch = "git_branch"
            case rolloutPath = "rollout_path"
            case updatedAtMilliseconds = "updated_at_ms"
        }
    }

    enum APIError: LocalizedError {
        case localCodexUnavailable(String)

        var errorDescription: String? {
            if case let .localCodexUnavailable(message) = self { return message }
            return nil
        }
    }
}
