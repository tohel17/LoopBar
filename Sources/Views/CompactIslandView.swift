import SwiftUI

/// Compact header pill: running count on one side and overall status on the other.
struct CompactIslandView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var viewModel: IslandViewModel

    private var expanded: Bool { viewModel.isExpandedChrome }
    private var runningCount: Int { store.agents.filter { $0.status == .running }.count }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                viewModel.toggleExpanded()
            }
        } label: {
            HStack(spacing: 0) {
                RunningCountView(count: runningCount)
                    .frame(width: 104, alignment: .leading)

                Spacer(minLength: 82)

                StatusBadge(status: islandStatus)
                    .frame(width: 118, alignment: .trailing)
            }
            .padding(.horizontal, expanded ? 18 : 14)
            .padding(.vertical, expanded ? 14 : 11)
        }
        .buttonStyle(.plain)
    }

    private var islandStatus: IslandStatus {
        if store.agents.contains(where: { $0.status.needsAttention }) {
            return .attention
        }
        if runningCount > 0 {
            return .running
        }
        return store.agents.isEmpty ? .waiting : .idle
    }
}

private enum IslandStatus {
    case running, attention, idle, waiting

    var title: String {
        switch self {
        case .running: "Running"
        case .attention: "Check"
        case .idle: "Idle"
        case .waiting: "Waiting"
        }
    }

    var symbol: String {
        switch self {
        case .running: "bolt.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .idle: "checkmark.circle.fill"
        case .waiting: "dot.radiowaves.left.and.right"
        }
    }

    var color: Color {
        switch self {
        case .running: .green
        case .attention: .orange
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

            Text("running")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
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
                .symbolEffect(.pulse, options: .repeating, value: status.title == "Running")

            Text(status.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
        }
        .lineLimit(1)
    }
}
