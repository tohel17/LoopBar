import AppKit
import Foundation

enum AgentOpener {
    static func open(_ agent: CursorAgent) {
        guard let url = agent.url else { return }
        open(url, source: agent.source)
    }

    static func open(_ url: URL, source: AgentSource? = nil) {
        switch source {
        case .cursor:
            open(url, bundleIdentifier: "com.todesktop.230313mzl4w4u92", fallbackPath: "/Applications/Cursor.app")
        case .codex:
            open(url, bundleIdentifier: "com.openai.codex", fallbackPath: "/Applications/ChatGPT.app")
        case .claude:
            // Claude Code has no stable GUI deep link. Open the project in Cursor
            // when available so we don't activate a random default editor (e.g.
            // Antigravity) that merely has the folder open.
            open(url, bundleIdentifier: "com.todesktop.230313mzl4w4u92", fallbackPath: "/Applications/Cursor.app")
        case nil:
            open(url, bundleIdentifier: "com.todesktop.230313mzl4w4u92", fallbackPath: "/Applications/Cursor.app")
        }
    }

    private static func open(_ url: URL, bundleIdentifier: String, fallbackPath: String) {
        let configuration = NSWorkspace.OpenConfiguration()
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
            return
        }

        let fallbackURL = URL(fileURLWithPath: fallbackPath)
        if FileManager.default.fileExists(atPath: fallbackURL.path) {
            NSWorkspace.shared.open([url], withApplicationAt: fallbackURL, configuration: configuration)
            return
        }

        NSWorkspace.shared.open(url)
    }
}
