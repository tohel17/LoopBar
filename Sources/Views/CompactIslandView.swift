import SwiftUI

/// Compact header pill: running count on one side and the most useful overall
/// status on the other. Attention states are intentionally specific so the
/// user can decide whether to act without expanding the island.
struct CompactIslandView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var viewModel: IslandViewModel

    private var expanded: Bool { viewModel.isExpandedChrome }
    private var runningCount: Int { store.agents.filter { $0.status == .running }.count }

    var body: some View {
        Button {
            viewModel.toggleExpanded()
        } label: {
            HStack(spacing: 0) {
                RunningCountView(count: runningCount)
                    .frame(width: 104, alignment: .leading)

                Spacer(minLength: 60)

                StatusBadge(status: islandStatus)
                    .frame(width: 118, alignment: .trailing)
            }
            .padding(.horizontal, expanded ? 30 : 32)
            .padding(.vertical, expanded ? 14 : 11)
        }
        .buttonStyle(.plain)
    }

    private var islandStatus: IslandStatus {
        let attentionAgents = store.agents.filter { $0.status.needsAttention }
        if !attentionAgents.isEmpty {
            let highestPriority = attentionAgents
                .map(\.status)
                .sorted { $0.attentionPriority > $1.attentionPriority }
                .first!
            return .attention(status: highestPriority, count: attentionAgents.count)
        }
        if runningCount > 0 {
            return .running
        }
        return store.agents.isEmpty ? .waiting : .idle
    }
}

private enum IslandStatus {
    case running
    case attention(status: AgentStatus, count: Int)
    case idle, waiting

    var title: String {
        switch self {
        case .running: "Running"
        case let .attention(status, count):
            count == 1 ? status.compactAttentionLabel : "\(count) need you"
        case .idle: "Idle"
        case .waiting: "Waiting"
        }
    }

    var symbol: String {
        switch self {
        case .running: "bolt.fill"
        case let .attention(status, _): status.compactAttentionSymbol
        case .idle: "checkmark.circle.fill"
        case .waiting: "dot.radiowaves.left.and.right"
        }
    }

    var color: Color {
        switch self {
        case .running: .green
        case let .attention(status, _): status.compactAttentionColor
        case .idle: .white
        case .waiting: .gray
        }
    }
}

private struct RunningCountView: View {
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(count)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

        }
        .lineLimit(1)
    }
}

private struct StatusBadge: View {
    let status: IslandStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(status.color)
                .symbolEffect(.pulse, options: .repeating, value: status.isAttention)

            Text(status.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
        }
        .lineLimit(1)
    }
}

private extension IslandStatus {
    var isAttention: Bool {
        if case .attention = self { return true }
        return false
    }
}

private extension AgentStatus {
    /// Approval/input are the most immediately actionable states, followed by
    /// blocked work and failures that need investigation.
    var attentionPriority: Int {
        switch self {
        case .waitingForApproval: 4
        case .waitingForInput: 3
        case .blocked: 2
        case .failed: 1
        default: 0
        }
    }

    var compactAttentionLabel: String {
        switch self {
        case .waitingForApproval: "Needs approval"
        case .waitingForInput: "Waiting"
        case .blocked: "Blocked"
        case .failed: "Failed"
        default: "Needs attention"
        }
    }

    var compactAttentionSymbol: String {
        switch self {
        case .waitingForApproval: "hand.raised.fill"
        case .waitingForInput: "person.crop.circle.badge.questionmark"
        case .blocked: "exclamationmark.octagon.fill"
        case .failed: "xmark.octagon.fill"
        default: "exclamationmark.triangle.fill"
        }
    }

    var compactAttentionColor: Color {
        switch self {
        case .waitingForApproval, .waitingForInput: .yellow
        case .blocked: .orange
        case .failed: .red
        default: .orange
        }
    }
}
