import Foundation

/// Reads recent local Codex threads without modifying Codex state.
struct CodexAPI {
    private let databaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/state_5.sqlite")

    func fetchAgents() async throws -> [CursorAgent] {
        try await Task.detached(priority: .userInitiated) {
            try self.readThreads(from: self.databaseURL)
        }.value
    }

    private func readThreads(from databaseURL: URL) throws -> [CursorAgent] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw APIError.localCodexUnavailable("Codex's local state database was not found.")
        }

        let query = """
            SELECT
                id,
                SUBSTR(COALESCE(NULLIF(title, ''), NULLIF(preview, ''), 'Untitled Codex task'), 1, 160) AS title,
                SUBSTR(COALESCE(NULLIF(preview, ''), NULLIF(first_user_message, ''), ''), 1, 240) AS preview,
                COALESCE(NULLIF(agent_nickname, ''), NULLIF(model, ''), NULLIF(model_provider, ''), 'Codex') AS detail,
                COALESCE(NULLIF(cwd, ''), '') AS cwd,
                COALESCE(NULLIF(git_branch, ''), '') AS git_branch,
                COALESCE(NULLIF(recency_at_ms, 0), NULLIF(updated_at_ms, 0), updated_at * 1000) AS updated_at_ms
            FROM threads
            WHERE archived = 0 AND source NOT LIKE '%subagent%'
            ORDER BY updated_at_ms DESC
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
            throw APIError.localCodexUnavailable(errorText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let now = Date()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let threads = try JSONDecoder().decode([LocalThread].self, from: data)
        return threads.map { thread in
            let updatedAt = Date(timeIntervalSince1970: thread.updatedAtMilliseconds / 1_000)
            let isActive = now.timeIntervalSince(updatedAt) < 120
            return CursorAgent(
                id: "codex-\(thread.id)",
                source: .codex,
                title: Self.displayTitle(from: thread.title),
                status: isActive ? .running : .unknown,
                progress: nil,
                latestStatus: Self.statusText(for: thread, updatedAt: updatedAt, isActive: isActive),
                updatedAt: updatedAt,
                url: Self.codexThreadURL(threadId: thread.id)
            )
        }
    }

    private static func codexThreadURL(threadId: String) -> URL? {
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "thread"
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

    private static func statusText(for thread: LocalThread, updatedAt: Date, isActive: Bool) -> String {
        let detail = thread.detail.isEmpty ? "Codex" : thread.detail
        let branch = thread.gitBranch.isEmpty ? "" : " · \(thread.gitBranch)"
        let location = URL(fileURLWithPath: thread.cwd).lastPathComponent
        let cwdLabel = location.isEmpty ? "" : " · \(location)"

        if isActive {
            return "Active in \(detail)\(branch)\(cwdLabel)"
        }
        return "Last active \(updatedAt.formatted(.relative(presentation: .named))) · \(detail)\(branch)\(cwdLabel)"
    }

    private struct LocalThread: Decodable {
        let id: String
        let title: String
        let preview: String
        let detail: String
        let cwd: String
        let gitBranch: String
        let updatedAtMilliseconds: Double

        enum CodingKeys: String, CodingKey {
            case id, title, preview, detail, cwd
            case gitBranch = "git_branch"
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
