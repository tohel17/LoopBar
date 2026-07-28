import Foundation

/// User-facing copy when the island has no agents to list.
enum EmptyAgentsCopy {
    static func title(lastUpdated: Date?, errorMessage: String?) -> String {
        if lastUpdated == nil {
            return "Connecting…"
        }
        if errorMessage != nil {
            return "Nothing to show yet"
        }
        return "No recent agents"
    }

    static func detail(
        lastUpdated: Date?,
        errorMessage: String?,
        cursorEnabled: Bool,
        codexEnabled: Bool,
        claudeEnabled: Bool
    ) -> String {
        if lastUpdated == nil {
            return "Checking enabled sources"
        }

        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }

        let enabled = [
            cursorEnabled ? "Cursor" : nil,
            codexEnabled ? "Codex" : nil,
            claudeEnabled ? "Claude" : nil
        ].compactMap { $0 }

        if enabled.isEmpty {
            return "Turn on Cursor, Codex, or Claude in Settings."
        }

        return "No recent \(enabled.joined(separator: "/")) activity on this Mac. Open a chat in one of those apps, then refresh."
    }
}
