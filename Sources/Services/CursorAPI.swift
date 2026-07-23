import Foundation

/// Reads Cursor's live composer headers without modifying Cursor's data.
///
/// Cursor stores lightweight composer headers separately from richer per-composer
/// state. We combine both local stores to infer live status without modifying
/// Cursor's data.
final class CursorAPI: @unchecked Sendable {
    // Cursor does not keep its live generation flags populated consistently
    // for long-running composers. Use the header recency window as the
    // fallback signal for active work.
    private static let activeWindow: TimeInterval = 15

    private let databaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    private let projectsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cursor/projects")
    private let transcriptMonitor = CursorTranscriptMonitor()
    private let processDiscovery = CursorDesktopProcessDiscovery()

    func fetchAgents() async throws -> [CursorAgent] {
        try await Task.detached(priority: .userInitiated) {
            try self.readComposers(
                from: self.databaseURL,
                projectsURL: self.projectsURL
            )
        }.value
    }

    private func readComposers(
        from databaseURL: URL,
        projectsURL: URL
    ) throws -> [CursorAgent] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw APIError.localCursorUnavailable("Cursor's local state database was not found.")
        }

        // Prefer lastUpdatedAt when present; otherwise fall back to recency/createdAt columns.
        let query = """
            SELECT
                h.composerId AS id,
                COALESCE(
                    NULLIF(json_extract(h.value, '$.name'), ''),
                    NULLIF(json_extract(h.value, '$.subtitle'), ''),
                    'Untitled local agent'
                ) AS title,
                NULLIF(json_extract(h.value, '$.subtitle'), '') AS subtitle,
                COALESCE(
                    json_extract(h.value, '$.lastUpdatedAt'),
                    h.lastUpdatedAt,
                    h.recency,
                    h.createdAt
                ) AS updated_at,
                COALESCE(json_extract(kv.value, '$.unifiedMode'), json_extract(h.value, '$.unifiedMode')) AS mode,
                COALESCE(
                    NULLIF(json_extract(h.value, '$.workspaceIdentifier.configPath.fsPath'), ''),
                    NULLIF(json_extract(h.value, '$.draftTarget.environment.configPath.fsPath'), '')
                ) AS workspace_path,
                NULLIF(json_extract(kv.value, '$.status'), '') AS composer_status,
                COALESCE(json_array_length(json_extract(kv.value, '$.generatingBubbleIds')), 0) AS generating_bubble_count,
                COALESCE(json_extract(kv.value, '$.isContinuationInProgress'), 0) AS is_continuation_in_progress,
                COALESCE(json_extract(kv.value, '$.isApplyingWorktree'), 0) AS is_applying_worktree,
                COALESCE(json_extract(kv.value, '$.isCreatingWorktree'), 0) AS is_creating_worktree,
                COALESCE(json_extract(kv.value, '$.isUndoingWorktree'), 0) AS is_undoing_worktree,
                COALESCE(json_array_length(json_extract(kv.value, '$.queueItems')), 0) AS queue_item_count,
                COALESCE(json_extract(kv.value, '$.hasBlockingPendingActions'), json_extract(h.value, '$.hasBlockingPendingActions'), 0) AS has_blocking_pending_actions,
                COALESCE(json_extract(h.value, '$.hasPendingPlan'), 0) AS has_pending_plan,
                COALESCE(json_extract(kv.value, '$.hasUnreadMessages'), json_extract(h.value, '$.hasUnreadMessages'), 0) AS has_unread_messages
            FROM composerHeaders h
            LEFT JOIN cursorDiskKV kv ON kv.key = 'composerData:' || h.composerId
            WHERE h.isArchived = 0
                AND h.isSubagent = 0
                AND COALESCE(json_extract(h.value, '$.isDraft'), json_extract(kv.value, '$.isDraft'), 0) = 0
            ORDER BY COALESCE(h.lastUpdatedAt, h.recency, h.createdAt) DESC
            LIMIT 3;
            """
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-readonly",
            "-cmd", ".timeout 500",
            "-json",
            databaseURL.path,
            query
        ]
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let errorText = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw APIError.localCursorUnavailable(errorText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let now = Date()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let composers = try JSONDecoder().decode([LocalComposer].self, from: data)
        let transcripts = transcriptMonitor.snapshots(
            for: Set(composers.map(\.id)),
            projectsURL: projectsURL
        )
        let isCursorRunning = processDiscovery.isRunning()
        return composers.map { composer in
            let databaseUpdatedAt = Date(
                timeIntervalSince1970: composer.updatedAt / 1_000
            )
            let transcript = transcripts[composer.id]
            let activityDate = max(
                databaseUpdatedAt,
                transcript?.modifiedAt ?? .distantPast
            )
            let isRecentlyActive = now.timeIntervalSince(activityDate)
                < Self.activeWindow
            let modeLabel = composer.mode.map { " · \($0)" } ?? ""
            let status = Self.status(
                for: composer,
                transcriptState: transcript?.state ?? .none,
                isRecentlyActive: isRecentlyActive,
                isCursorRunning: isCursorRunning
            )
            return CursorAgent(
                id: composer.id,
                title: composer.title,
                status: status,
                progress: nil,
                latestStatus: Self.statusText(
                    for: status,
                    updatedAt: activityDate,
                    modeLabel: modeLabel
                ),
                updatedAt: activityDate,
                url: Self.cursorAgentURL(composer: composer)
            )
        }
    }

    private static func status(
        for composer: LocalComposer,
        transcriptState: CursorTranscriptMonitor.TurnState,
        isRecentlyActive: Bool,
        isCursorRunning: Bool?
    ) -> AgentStatus {
        let explicitStatus = AgentStatus(apiValue: composer.composerStatus)

        // Process state is only an app-level guard. If Cursor Desktop is
        // closed, preserve durable terminal evidence but do not present stale
        // approval, queue, or generation fields as live work.
        if isCursorRunning == false {
            switch transcriptState {
            case .completed:
                return .completed
            case .failed:
                return .failed
            case .none, .running:
                break
            }
            if explicitStatus.isTerminal {
                return explicitStatus
            }
            if composer.hasCompletionSubtitle {
                return .completed
            }
            return .unknown
        }

        if explicitStatus == .blocked {
            return .blocked
        }
        if composer.hasPendingPlan {
            return .waitingForApproval
        }
        if composer.hasUnreadMessages {
            return .waitingForInput
        }
        if composer.hasBlockingPendingActions {
            return .waitingForApproval
        }
        if composer.isActivelyGenerating {
            return .running
        }
        if composer.queueItemCount > 0 {
            return .queued
        }

        switch transcriptState {
        case .running:
            return .running
        case .completed:
            return .completed
        case .failed:
            return .failed
        case .none:
            break
        }

        if explicitStatus != .unknown {
            return explicitStatus
        }
        if composer.hasCompletionSubtitle {
            return .completed
        }
        return isRecentlyActive ? .running : .unknown
    }

    private static func statusText(for status: AgentStatus, updatedAt: Date, modeLabel: String) -> String {
        switch status {
        case .blocked:
            return "Blocked in Cursor\(modeLabel)"
        case .waitingForApproval:
            return "Plan or action needs approval\(modeLabel)"
        case .waitingForInput:
            return "Waiting for your response\(modeLabel)"
        case .running:
            return "Active in Cursor\(modeLabel)"
        case .completed:
            return "Completed in Cursor\(modeLabel)"
        case .failed:
            return "Failed in Cursor\(modeLabel)"
        default:
            return "Last active \(updatedAt.formatted(.relative(presentation: .named)))\(modeLabel)"
        }
    }

    /// Cursor does not expose a confirmed external route for opening a specific
    /// composer. Prefer opening the associated workspace in Cursor; that gets
    /// the user to the right project/window without relying on fake deep links.
    private static func cursorAgentURL(composer: LocalComposer) -> URL? {
        guard let workspacePath = composer.workspacePath, !workspacePath.isEmpty else {
            return URL(string: "cursor://")
        }
        return URL(fileURLWithPath: workspacePath)
    }

    private struct LocalComposer: Decodable {
        let id: String
        let title: String
        let subtitle: String?
        let updatedAt: Double
        let mode: String?
        let workspacePath: String?
        let composerStatus: String?
        let generatingBubbleCount: Int
        let isContinuationInProgress: Bool
        let isApplyingWorktree: Bool
        let isCreatingWorktree: Bool
        let isUndoingWorktree: Bool
        let queueItemCount: Int
        let hasBlockingPendingActions: Bool
        let hasPendingPlan: Bool
        let hasUnreadMessages: Bool

        var isActivelyGenerating: Bool {
            generatingBubbleCount > 0
                || isContinuationInProgress
                || isApplyingWorktree
                || isCreatingWorktree
                || isUndoingWorktree
        }

        var hasCompletionSubtitle: Bool {
            guard let subtitle else { return false }
            let normalizedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedSubtitle.range(
                of: "Edited ",
                options: [.caseInsensitive, .anchored]
            ) != nil
        }

        enum CodingKeys: String, CodingKey {
            case id, title, subtitle, mode
            case workspacePath = "workspace_path"
            case composerStatus = "composer_status"
            case generatingBubbleCount = "generating_bubble_count"
            case isContinuationInProgress = "is_continuation_in_progress"
            case isApplyingWorktree = "is_applying_worktree"
            case isCreatingWorktree = "is_creating_worktree"
            case isUndoingWorktree = "is_undoing_worktree"
            case queueItemCount = "queue_item_count"
            case updatedAt = "updated_at"
            case hasBlockingPendingActions = "has_blocking_pending_actions"
            case hasPendingPlan = "has_pending_plan"
            case hasUnreadMessages = "has_unread_messages"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
            updatedAt = try container.decode(Double.self, forKey: .updatedAt)
            mode = try container.decodeIfPresent(String.self, forKey: .mode)
            workspacePath = try container.decodeIfPresent(String.self, forKey: .workspacePath)
            composerStatus = try container.decodeIfPresent(String.self, forKey: .composerStatus)
            generatingBubbleCount = try container.decodeIfPresent(Int.self, forKey: .generatingBubbleCount) ?? 0
            isContinuationInProgress = try Self.decodeSQLiteBool(container, .isContinuationInProgress)
            isApplyingWorktree = try Self.decodeSQLiteBool(container, .isApplyingWorktree)
            isCreatingWorktree = try Self.decodeSQLiteBool(container, .isCreatingWorktree)
            isUndoingWorktree = try Self.decodeSQLiteBool(container, .isUndoingWorktree)
            queueItemCount = try container.decodeIfPresent(Int.self, forKey: .queueItemCount) ?? 0
            hasBlockingPendingActions = try Self.decodeSQLiteBool(container, .hasBlockingPendingActions)
            hasPendingPlan = try Self.decodeSQLiteBool(container, .hasPendingPlan)
            hasUnreadMessages = try Self.decodeSQLiteBool(container, .hasUnreadMessages)
        }

        private static func decodeSQLiteBool(
            _ container: KeyedDecodingContainer<CodingKeys>,
            _ key: CodingKeys
        ) throws -> Bool {
            if let bool = try? container.decode(Bool.self, forKey: key) {
                return bool
            }
            if let int = try? container.decode(Int.self, forKey: key) {
                return int != 0
            }
            return false
        }
    }

    enum APIError: LocalizedError {
        case localCursorUnavailable(String)

        var errorDescription: String? {
            if case let .localCursorUnavailable(message) = self { return message }
            return nil
        }
    }
}
