import AppKit
import SwiftUI

/// Single agent row in the expanded agents list.
struct AgentRowView: View {
    let agent: CursorAgent

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(0.16))
                Image(systemName: agent.status.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(agent.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(agent.status.label)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(color.opacity(0.9))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.14), in: Capsule())
                }
                Text(agent.latestStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                if let progress = agent.progress, agent.status == .running {
                    ProgressView(value: progress)
                        .tint(color)
                        .scaleEffect(y: 0.6, anchor: .center)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 11)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { openInCursor(agent) }
    }

    private var color: Color {
        switch agent.status {
        case .running: .purple
        case .queued: .yellow
        case .completed: .green
        case .failed: .red
        case .cancelled, .unknown: .gray
        }
    }

    private func openInCursor(_ agent: CursorAgent) {
        guard let url = agent.url else { return }
        let cursorApp = URL(fileURLWithPath: "/Applications/Cursor.app")
        if FileManager.default.fileExists(atPath: cursorApp.path) {
            NSWorkspace.shared.open([url], withApplicationAt: cursorApp, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
