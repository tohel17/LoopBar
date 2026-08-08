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
                COALESCE(approval_mode, '') AS approval_mode,
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
        let semanticStatus = status(
            fromRolloutAt: thread.rolloutPath,
            approvalMode: thread.approvalMode
        )
        return reconciledStatus(
            semanticStatus: semanticStatus,
            isProcessLive: isProcessLive,
            canDetermineProcessAbsence: canDetermineProcessAbsence,
            isRecentlyActive: isRecentlyActive
        )
    }

    static func reconciledStatus(
        semanticStatus: AgentStatus,
        isProcessLive: Bool,
        canDetermineProcessAbsence: Bool,
        isRecentlyActive: Bool
    ) -> AgentStatus {
        if isProcessLive {
            return semanticStatus == .unknown ? .running : semanticStatus
        }
        if semanticStatus.isTerminal {
            return semanticStatus
        }
        if canDetermineProcessAbsence {
            return .unknown
        }
        // Desktop/app-server tasks are not terminal-attached processes. Their
        // task_started/task_complete lifecycle is the authoritative liveness
        // signal, including while a local command is quiet for several minutes.
        if semanticStatus != .unknown {
            return semanticStatus
        }
        return isRecentlyActive ? .running : .unknown
    }

    /// Derives task state from structured rollout records. Pending approval and
    /// input calls remain unresolved until a matching call_id output is written.
    /// Parsing records avoids matching status-looking strings inside messages or
    /// command output.
    static func status(
        fromRollout rollout: String,
        isRecentlyUpdated: Bool,
        approvalMode: String = "on-request",
        fallbackLifecycle: AgentStatus? = nil
    ) -> AgentStatus {
        var lifecycle = fallbackLifecycle ?? .unknown
        var approvalCalls = Set<String>()
        var inputCalls = Set<String>()
        var legacyApprovalPending = false
        var legacyInputPending = false
        var blocked = false
        let decoder = JSONDecoder()

        for line in rollout.split(whereSeparator: \.isNewline) {
            guard let record = try? decoder.decode(
                RolloutRecord.self,
                from: Data(line.utf8)
            ) else {
                continue
            }

            switch record.payload.type {
            case "task_started":
                lifecycle = .running
                approvalCalls.removeAll()
                inputCalls.removeAll()
                legacyApprovalPending = false
                legacyInputPending = false
                blocked = false
            case "task_complete":
                lifecycle = .completed
                approvalCalls.removeAll()
                inputCalls.removeAll()
                legacyApprovalPending = false
                legacyInputPending = false
                blocked = false
            case "turn_aborted":
                lifecycle = .cancelled
                approvalCalls.removeAll()
                inputCalls.removeAll()
                legacyApprovalPending = false
                legacyInputPending = false
                blocked = false
            case "execCommandApproval", "applyPatchApproval",
                 "permissions_request_approval",
                 "command_execution_request_approval",
                 "file_change_request_approval":
                legacyApprovalPending = true
            case "tool_request_user_input", "request_user_input":
                legacyInputPending = true
            case "goal_updated":
                blocked = record.payload.status?.lowercased() == "blocked"
            case "user_message":
                legacyInputPending = false
            case "function_call_output", "custom_tool_call_output":
                if let callID = record.payload.callID {
                    approvalCalls.remove(callID)
                    inputCalls.remove(callID)
                }
                legacyApprovalPending = false
                legacyInputPending = false
            case "function_call", "custom_tool_call":
                guard let callID = record.payload.callID else { break }
                if Self.isApprovalRequest(record.payload, approvalMode: approvalMode) {
                    approvalCalls.insert(callID)
                }
                if Self.isInputRequest(record.payload) {
                    inputCalls.insert(callID)
                }
            default:
                if record.payload.status?.lowercased() == "blocked" {
                    blocked = true
                }
            }
        }

        if !approvalCalls.isEmpty || legacyApprovalPending {
            return .waitingForApproval
        }
        if !inputCalls.isEmpty || legacyInputPending {
            return .waitingForInput
        }
        if blocked {
            return .blocked
        }
        return lifecycle == .unknown && isRecentlyUpdated ? .running : lifecycle
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

    static func status(
        fromRolloutAt path: String,
        approvalMode: String,
        isRecentlyUpdated: Bool = false
    ) -> AgentStatus {
        let tail = rolloutTail(at: path)
        let fallbackLifecycle = lifecycleStatus(in: tail.text) == nil
            ? latestLifecycle(at: path, beforeOffset: tail.startOffset)
            : nil
        return status(
            fromRollout: tail.text,
            isRecentlyUpdated: isRecentlyUpdated,
            approvalMode: approvalMode,
            fallbackLifecycle: fallbackLifecycle
        )
    }

    private static func rolloutTail(at path: String) -> RolloutTail {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            return RolloutTail(text: "", startOffset: 0)
        }
        do {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer { try? handle.close() }
            let fileSize = try handle.seekToEnd()
            let tailSize: UInt64 = 1_024 * 1_024
            let startOffset = fileSize > tailSize ? fileSize - tailSize : 0
            try handle.seek(toOffset: startOffset)
            let text = String(
                decoding: handle.readDataToEndOfFile(),
                as: UTF8.self
            )
            return RolloutTail(text: text, startOffset: startOffset)
        } catch {
            return RolloutTail(text: "", startOffset: 0)
        }
    }

    /// Finds the latest lifecycle marker preceding the bounded rollout tail.
    /// This keeps long, quiet command turns active without rereading a many-MB
    /// transcript on every one-second poll.
    private static func latestLifecycle(
        at path: String,
        beforeOffset: UInt64
    ) -> AgentStatus? {
        guard beforeOffset > 0,
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return nil
        }
        defer { try? handle.close() }

        let chunkSize: UInt64 = 256 * 1_024
        var endOffset = beforeOffset
        var laterPrefix = Data()

        while endOffset > 0 {
            let startOffset = endOffset > chunkSize ? endOffset - chunkSize : 0
            do {
                try handle.seek(toOffset: startOffset)
                var data = handle.readData(ofLength: Int(endOffset - startOffset))
                data.append(laterPrefix)
                let text = String(decoding: data, as: UTF8.self)
                if let status = lifecycleStatus(in: text) {
                    return status
                }
                laterPrefix = data.prefix(256)
                endOffset = startOffset
            } catch {
                return nil
            }
        }
        return nil
    }

    private static func lifecycleStatus(in text: String) -> AgentStatus? {
        let markers: [(String, AgentStatus)] = [
            ("\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"", .running),
            ("\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"", .completed),
            ("\"type\":\"event_msg\",\"payload\":{\"type\":\"turn_aborted\"", .cancelled)
        ]
        return markers
            .compactMap { marker -> (Int, AgentStatus)? in
                guard let index = latestIndex(of: marker.0, in: text) else { return nil }
                return (index, marker.1)
            }
            .max { $0.0 < $1.0 }?
            .1
    }

    private static func isApprovalRequest(
        _ payload: RolloutPayload,
        approvalMode: String
    ) -> Bool {
        guard approvalMode.lowercased() != "never" else { return false }
        let content = (payload.arguments ?? payload.input ?? "").lowercased()
        return content.contains("sandbox_permissions")
            && content.contains("require_escalated")
    }

    private static func isInputRequest(_ payload: RolloutPayload) -> Bool {
        let name = payload.name?.lowercased()
        return name == "request_user_input" || name == "tool_request_user_input"
    }

    private static func latestIndex(of needle: String, in haystack: String) -> Int? {
        guard let range = haystack.range(of: needle, options: [.backwards]) else {
            return nil
        }
        return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
    }

    private struct RolloutTail {
        let text: String
        let startOffset: UInt64
    }

    private struct RolloutRecord: Decodable {
        let type: String
        let payload: RolloutPayload
    }

    private struct RolloutPayload: Decodable {
        let type: String
        let name: String?
        let callID: String?
        let arguments: String?
        let input: String?
        let status: String?

        enum CodingKeys: String, CodingKey {
            case type, name, arguments, input, status
            case callID = "call_id"
        }
    }

    private struct LocalThread: Decodable {
        let id: String
        let title: String
        let preview: String
        let detail: String
        let cwd: String
        let gitBranch: String
        let source: String
        let approvalMode: String
        let rolloutPath: String
        let updatedAtMilliseconds: Double

        var isTerminalSource: Bool {
            let normalized = source.lowercased()
            return normalized.contains("cli") || normalized.contains("terminal")
        }

        enum CodingKeys: String, CodingKey {
            case id, title, preview, detail, cwd, source
            case gitBranch = "git_branch"
            case approvalMode = "approval_mode"
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
