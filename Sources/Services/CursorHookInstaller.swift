import Foundation

/// Installs LoopBar's observational Cursor hook without replacing user hooks.
enum CursorHookInstaller {
    private static let hookName = "loopbar-cursor-hook.py"
    private static let hookCommand = "~/.cursor/hooks/loopbar-cursor-hook.py"
    private static let events = [
        "sessionStart", "afterAgentResponse", "afterAgentThought",
        "beforeShellExecution", "afterShellExecution",
        "beforeMCPExecution", "afterMCPExecution",
        "preToolUse", "postToolUse", "stop", "sessionEnd"
    ]

    static func install() {
        let fileManager = FileManager.default
        let cursorDirectory = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".cursor")
        let hooksDirectory = cursorDirectory.appendingPathComponent("hooks")
        let scriptURL = hooksDirectory.appendingPathComponent(hookName)
        let configURL = cursorDirectory.appendingPathComponent("hooks.json")

        do {
            try fileManager.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)
            guard let bundledScript = Bundle.module.url(
                forResource: hookName,
                withExtension: nil
            ) else { return }
            try fileManager.removeItemIfPresent(at: scriptURL)
            try fileManager.copyItem(at: bundledScript, to: scriptURL)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            var config = try existingConfig(at: configURL)
            var hooks = config["hooks"] as? [String: Any] ?? [:]
            for event in events {
                hooks[event] = [["command": "\(hookCommand) \(event)"]]
            }
            config["version"] = 1
            config["hooks"] = hooks
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configURL, options: .atomic)
        } catch {
            // Monitoring still works through SQLite/transcripts if hook setup
            // is unavailable or the user's existing config is malformed.
        }
    }

    private static func existingConfig(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        guard let config = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallerError.invalidConfig
        }
        return config
    }

    private enum InstallerError: Error { case invalidConfig }
}

private extension FileManager {
    func removeItemIfPresent(at url: URL) throws {
        if fileExists(atPath: url.path) { try removeItem(at: url) }
    }
}
