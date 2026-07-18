import Foundation

/// Reads Cursor's local conversation index without modifying Cursor's data.
/// Cursor does not expose a durable local run state, so a conversation updated within
/// the last two minutes is treated as active and all other conversations are unknown.
struct LocalCursorAgentAPI {
    private let databaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/conversation-search.db")

    func fetchAgents() async throws -> [CursorAgent] {
        try await Task.detached(priority: .userInitiated) {
            try readConversations(from: databaseURL)
        }.value
    }

    private func readConversations(from databaseURL: URL) throws -> [CursorAgent] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw APIError.localCursorUnavailable("Cursor's local conversation index was not found.")
        }

        let query = """
            SELECT id, title, updated_at
            FROM conversations
            WHERE source = 'local' AND is_archived = 0
            ORDER BY updated_at DESC
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
        let conversations = try JSONDecoder().decode([LocalConversation].self, from: data)
        let agents = conversations.map { conversation in
            let updatedAt = Date(timeIntervalSince1970: conversation.updatedAt / 1_000)
            let isActive = now.timeIntervalSince(updatedAt) < 120
            return CursorAgent(
                id: conversation.id,
                title: conversation.title.isEmpty ? "Untitled local agent" : conversation.title,
                status: isActive ? .running : .unknown,
                progress: nil,
                latestStatus: isActive ? "Active in Cursor" : "Last active \(updatedAt.formatted(.relative(presentation: .named)))",
                updatedAt: updatedAt,
                url: nil
            )
        }
        print("[Cursor Local] decoded \(agents.count) agents")
        return agents
    }

    private struct LocalConversation: Decodable {
        let id: String
        let title: String
        let updatedAt: Double

        enum CodingKeys: String, CodingKey {
            case id, title
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
