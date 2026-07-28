import Foundation

/// Resolves what a notification click should open.
///
/// Cursor agents use `file://` workspace paths (Cursor has no stable composer deep
/// link). Inferring source from the URL scheme alone therefore mis-routed Cursor
/// clicks through the Claude/default path and activated whatever editor last
/// claimed the folder (e.g. Antigravity IDE).
struct NotificationOpenTarget: Equatable {
    let url: URL
    let source: AgentSource

    static func open(url: URL, source: AgentSource) -> NotificationOpenTarget {
        NotificationOpenTarget(url: url, source: source)
    }

    static func resolve(agentURL: String?, agentSource: String?) -> NotificationOpenTarget? {
        guard
            let agentURL,
            let url = URL(string: agentURL),
            url.scheme != nil
        else {
            return nil
        }

        if let agentSource, let source = AgentSource(rawValue: agentSource) {
            return .open(url: url, source: source)
        }

        switch url.scheme?.lowercased() {
        case "codex":
            return .open(url: url, source: .codex)
        case "cursor":
            return .open(url: url, source: .cursor)
        case "file":
            // Prefer Cursor for bare file URLs — both Cursor and Claude use file
            // paths, and Cursor is the primary editor LoopBar opens into.
            return .open(url: url, source: .cursor)
        default:
            return .open(url: url, source: .cursor)
        }
    }
}
