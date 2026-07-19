import Foundation

/// Reads Cursor's live composer headers without modifying Cursor's data.
///
/// Cursor does not expose a durable local run state, so a composer updated within
/// the last two minutes is treated as active and all other composers are unknown.
struct CursorAPI {
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
                composerId AS id,
                COALESCE(
                    NULLIF(json_extract(value, '$.name'), ''),
                    NULLIF(json_extract(value, '$.subtitle'), ''),
                    'Untitled local agent'
                ) AS title,
                COALESCE(
                    json_extract(value, '$.lastUpdatedAt'),
                    lastUpdatedAt,
                    recency,
                    createdAt
                ) AS updated_at,
                json_extract(value, '$.unifiedMode') AS mode,
                COALESCE(json_extract(value, '$.hasBlockingPendingActions'), 0) AS has_blocking_pending_actions,
                COALESCE(json_extract(value, '$.hasPendingPlan'), 0) AS has_pending_plan,
                COALESCE(json_extract(value, '$.hasUnreadMessages'), 0) AS has_unread_messages
            FROM composerHeaders
            WHERE isArchived = 0 AND isSubagent = 0
            ORDER BY COALESCE(lastUpdatedAt, recency, createdAt) DESC
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
            let isActive = now.timeIntervalSince(updatedAt) < 120
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

    private static func status(for composer: LocalComposer, isActive: Bool) -> AgentStatus {
        if composer.hasBlockingPendingActions {
            return .blocked
        }
        if composer.hasPendingPlan {
            return .waitingForApproval
        }
        if composer.hasUnreadMessages {
            return .waitingForInput
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
        let updatedAt: Double
        let mode: String?
        let hasBlockingPendingActions: Bool
        let hasPendingPlan: Bool
        let hasUnreadMessages: Bool

        enum CodingKeys: String, CodingKey {
            case id, title, mode
            case updatedAt = "updated_at"
            case hasBlockingPendingActions = "has_blocking_pending_actions"
            case hasPendingPlan = "has_pending_plan"
            case hasUnreadMessages = "has_unread_messages"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            updatedAt = try container.decode(Double.self, forKey: .updatedAt)
            mode = try container.decodeIfPresent(String.self, forKey: .mode)
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
