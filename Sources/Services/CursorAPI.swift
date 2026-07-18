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
                json_extract(value, '$.unifiedMode') AS mode
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
        let response = String(data: data, encoding: .utf8) ?? "<non-UTF-8 response: \(data.count) bytes>"
        print("[Cursor Local] response:\n\(response)")
        let composers = try JSONDecoder().decode([LocalComposer].self, from: data)
        let agents = composers.map { composer in
            let updatedAt = Date(timeIntervalSince1970: composer.updatedAt / 1_000)
            let isActive = now.timeIntervalSince(updatedAt) < 120
            let modeLabel = composer.mode.map { " · \($0)" } ?? ""
            return CursorAgent(
                id: composer.id,
                title: composer.title,
                status: isActive ? .running : .unknown,
                progress: nil,
                latestStatus: isActive
                    ? "Active in Cursor\(modeLabel)"
                    : "Last active \(updatedAt.formatted(.relative(presentation: .named)))\(modeLabel)",
                updatedAt: updatedAt,
                url: Self.cursorAgentURL(composerId: composer.id)
            )
        }
        print("[Cursor Local] decoded \(agents.count) agents")
        return agents
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

        enum CodingKeys: String, CodingKey {
            case id, title, mode
            case updatedAt = "updated_at"
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
