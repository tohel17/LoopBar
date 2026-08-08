import SwiftUI

/// Single agent row in the expanded agents list.
struct AgentRowView: View {
    let agent: CursorAgent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            row(now: timeline.date)
        }
    }

    private func row(now: Date) -> some View {
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
                    Text(agent.source.rawValue)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.10), in: Capsule())
                    Text(AgentElapsedText.statusLabel(for: agent, now: now))
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
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { AgentOpener.open(agent) }
    }

    private var color: Color {
        switch agent.status {
        case .running:
            switch agent.source {
            case .cursor: .purple
            case .codex: .blue
            case .claude: .claudeRunning
            }
        case .queued: .yellow
        case .waitingForApproval: .orange
        case .waitingForInput: .cyan
        case .blocked: .red
        case .completed: .green
        case .failed: .red
        case .cancelled, .unknown: .gray
        }
    }

}
