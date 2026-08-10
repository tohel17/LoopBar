import SwiftUI

/// Single agent row in the expanded agents list.
struct AgentRowView: View {
    let agent: CursorAgent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            Button {
                AgentOpener.open(agent)
            } label: {
                row(now: timeline.date)
            }
            .buttonStyle(.plain)
            .scaleEffect(isHovering && !reduceMotion ? 1.008 : 1)
            .onHover { hovering in
                withAnimation(hoverAnimation) {
                    isHovering = hovering
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(now: timeline.date))
            .accessibilityHint("Opens this task in \(agent.source.rawValue)")
            .help("Open in \(agent.source.rawValue)")
        }
    }

    private func row(now: Date) -> some View {
        HStack(alignment: .center, spacing: 11) {
            ZStack {
                Circle()
                    .fill(agent.source.accentColor.opacity(0.14))
                Circle()
                    .strokeBorder(
                        agent.source.accentColor.opacity(agent.status == .running ? 0.72 : 0.30),
                        lineWidth: agent.status == .running ? 1.2 : 0.8
                    )
                Image(systemName: agent.source.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(agent.source.accentColor)
                    .symbolEffect(
                        .pulse,
                        options: .repeating,
                        value: !reduceMotion && agent.status == .running
                    )
            }
            .frame(width: 32, height: 32)
            .overlay(alignment: .bottomTrailing) {
                if agent.status.needsAttention {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .overlay {
                            Circle()
                                .strokeBorder(.black.opacity(0.75), lineWidth: 1.5)
                        }
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(agent.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Label(agent.source.rawValue, systemImage: agent.source.symbol)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(agent.source.accentColor.opacity(0.95))
                        .labelStyle(.titleAndIcon)
                        .fixedSize()

                    Text(AgentElapsedText.statusLabel(for: agent, now: now))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(statusColor.opacity(0.95))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.13), in: Capsule())
                        .fixedSize()
                }

                Text(agent.latestStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.54))
                    .lineLimit(1)

                if let progress = agent.progress, agent.status == .running {
                    ProgressView(value: progress)
                        .tint(agent.source.accentColor)
                        .scaleEffect(y: 0.58, anchor: .center)
                        .animation(progressAnimation, value: progress)
                        .accessibilityLabel("Progress")
                        .accessibilityValue("\(Int(progress * 100)) percent")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(rowGradient)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(
                    .white.opacity(isHovering ? 0.16 : 0.10),
                    lineWidth: isHovering ? 1.0 : 0.8
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var rowGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: agent.source.accentColor.opacity(isHovering ? 0.24 : 0.18), location: 0),
                .init(color: agent.source.accentColor.opacity(isHovering ? 0.12 : 0.09), location: 0.58),
                .init(color: agent.source.accentColor.opacity(isHovering ? 0.08 : 0.05), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var statusColor: Color {
        switch agent.status {
        case .running:
            agent.source.accentColor
        case .queued: .yellow
        case .waitingForApproval: .orange
        case .waitingForInput: .cyan
        case .blocked: .red
        case .completed: .green
        case .failed: .red
        case .cancelled, .unknown: .gray
        }
    }

    private var hoverAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.16)
    }

    private var progressAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.24)
    }

    private func accessibilityLabel(now: Date) -> String {
        [
            agent.title,
            agent.source.rawValue,
            AgentElapsedText.statusLabel(for: agent, now: now),
            agent.latestStatus
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }
}
