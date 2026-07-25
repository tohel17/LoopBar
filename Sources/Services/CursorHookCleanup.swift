import Foundation

/// Removes LoopBar's legacy observational hook while preserving unrelated
/// commands in the user's Cursor hook configuration.
enum CursorHookCleanup {
    private static let hookCommand = "~/.cursor/hooks/loopbar-cursor-hook.py"

    static func removeLegacyInstallation() {
        let fileManager = FileManager.default
        let cursorDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor")
        let scriptURL = cursorDirectory
            .appendingPathComponent("hooks/loopbar-cursor-hook.py")
        let stateURL = cursorDirectory
            .appendingPathComponent("loopbar-agent-events.jsonl")
        let configURL = cursorDirectory.appendingPathComponent("hooks.json")

        try? fileManager.removeItemIfPresent(at: scriptURL)
        try? fileManager.removeItemIfPresent(at: stateURL)
        removeCommands(from: configURL)
    }

    private static func removeCommands(from configURL: URL) {
        guard let data = try? Data(contentsOf: configURL),
              var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = config["hooks"] as? [String: Any] else {
            return
        }

        var changed = false
        for (event, value) in hooks {
            guard let commands = value as? [[String: Any]] else { continue }
            let filtered = commands.filter {
                guard let command = $0["command"] as? String else { return true }
                return !command.contains(hookCommand)
            }
            guard filtered.count != commands.count else { continue }
            changed = true
            if filtered.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = filtered
            }
        }

        guard changed else { return }
        config["hooks"] = hooks
        guard let updated = try? JSONSerialization.data(
            withJSONObject: config,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return
        }
        try? updated.write(to: configURL, options: .atomic)
    }
}

private extension FileManager {
    func removeItemIfPresent(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}
