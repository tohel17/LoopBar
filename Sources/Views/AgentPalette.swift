import SwiftUI

extension Color {
    /// Claude's terracotta (#da7756), used wherever a Claude session is running.
    static let claudeRunning = Color(red: 218 / 255, green: 119 / 255, blue: 86 / 255)
}

extension AgentSource {
    /// Source identity is deliberately consistent across rows, settings, and
    /// compact chrome. Status colors remain separate so "Codex" never becomes
    /// indistinguishable from "completed", for example.
    var accentColor: Color {
        switch self {
        case .cursor: .purple
        case .codex: .blue
        case .claude: .claudeRunning
        }
    }

    var secondaryAccentColor: Color {
        switch self {
        case .cursor: .indigo
        case .codex: .cyan
        case .claude: .orange
        }
    }

    var symbol: String {
        switch self {
        case .cursor: "cursorarrow.rays"
        case .codex: "sparkles"
        case .claude: "sparkle"
        }
    }
}
