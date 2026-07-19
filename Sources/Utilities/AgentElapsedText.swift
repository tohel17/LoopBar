import Foundation

enum AgentElapsedText {
    static func short(since date: Date?, now: Date) -> String? {
        guard let date else { return nil }

        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 {
            return "\(max(seconds, 1))s"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h"
        }

        return "\(hours / 24)d"
    }

    static func statusLabel(for agent: CursorAgent, now: Date) -> String {
        guard let elapsed = short(since: agent.updatedAt, now: now) else {
            return agent.status.label
        }

        if agent.status.isTerminal {
            return "\(agent.status.label) · \(elapsed) ago"
        }
        return "\(agent.status.label) · \(elapsed)"
    }
}
