import Foundation

/// Reads Cursor's live composer headers without modifying Cursor's data.
///
/// Cursor stores lightweight composer headers separately from richer per-composer
/// state. We combine both local stores to infer live status without modifying
/// Cursor's data.
struct CursorAPI {
    private static let activeWindow: TimeInterval = 20

    private let databaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")

    func fetchAgents() async throws -> [CursorAgent] {
        try await Task.detached(priority: .userInitiated) {
            try self.readComposers(from: self.databaseURL)
        }.value
    }

    private func readComposers(from databaseURL: URL) throws -> [CursorAgent] {
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
        process.arguments = ["-readonly", "-json", databaseURL.path, query]
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
        return composers.map { composer in
            let updatedAt = Date(timeIntervalSince1970: composer.updatedAt / 1_000)
            let isActive = now.timeIntervalSince(updatedAt) < Self.activeWindow
            let modeLabel = composer.mode.map { " · \($0)" } ?? ""
            let status = Self.status(for: composer, isActive: isActive)
            return CursorAgent(
                id: composer.id,
                title: composer.title,
                status: status,
                progress: nil,
                latestStatus: Self.statusText(for: status, updatedAt: updatedAt, modeLabel: modeLabel),
                updatedAt: updatedAt,
                url: Self.cursorAgentURL(composerId: composer.id)
            )
        }
    }

    private static func status(
        for composer: LocalComposer,
        isActive: Bool
    ) -> AgentStatus {
        if composer.hasBlockingPendingActions {
            return .blocked
        }
        if composer.hasPendingPlan {
            return .waitingForApproval
        }
        if composer.hasUnreadMessages {
            return .waitingForInput
        }
        if composer.isActivelyGenerating {
            return .running
        }
        if composer.queueItemCount > 0 {
            return .queued
        }
        let explicitStatus = AgentStatus(apiValue: composer.composerStatus)
        if explicitStatus != .unknown {
            return explicitStatus
        }
        if composer.hasCompletionSubtitle {
            return .completed
        }
        return isActive ? .running : .unknown
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
        default:
            return "Last active \(updatedAt.formatted(.relative(presentation: .named)))\(modeLabel)"
        }
    }

    /// Cursor's internal agent-link scheme: `cursor.agent://local/<composerId>`.
    private static func cursorAgentURL(composerId: String) -> URL? {
        var components = URLComponents()
        components.scheme = "cursor.agent"
        components.host = "local"
        components.path = "/\(composerId)"
        return components.url
    }

    private struct LocalComposer: Decodable {
        let id: String
        let title: String
        let subtitle: String?
        let updatedAt: Double
        let mode: String?
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
