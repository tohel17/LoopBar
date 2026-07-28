import SwiftUI

/// Compact header pill: running count on one side and the most useful overall
/// status on the other. Attention states are intentionally specific so the
/// user can decide whether to act without expanding the island.
struct CompactIslandView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var viewModel: IslandViewModel

    private var expanded: Bool { viewModel.isExpandedChrome }
    private var runningCount: Int { store.agents.filter { $0.status == .running }.count }
    private var attentionCount: Int { store.agents.filter { $0.status.needsAttention }.count }
    private var hasAgents: Bool { !store.agents.isEmpty }

    var body: some View {
        Button {
            viewModel.toggleExpanded()
        } label: {
            HStack(spacing: 0) {
                if hasAgents {
                    CountChip(count: runningCount, label: "run", symbol: "bolt.fill", color: runningColor)
                        .frame(width: 86, alignment: .leading)

                    Spacer(minLength: 116)

                    CountChip(count: attentionCount, label: "wait", symbol: attentionSymbol, color: attentionColor)
                        .frame(width: 86, alignment: .trailing)
                } else {
                    StatusBadge(status: store.lastUpdated == nil ? .waiting : .idle)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, expanded ? 30 : 32)
            .padding(.vertical, expanded ? 14 : 11)
            .background {
                // Keep the accent attached to the island itself.  Applying it
                // to the tiny count label made most of the glow fall outside
                // the label's bounds and become effectively invisible.
                ZStack {
                    Color.black

                    if runningCount > 0 {
                        RadialGradient(
                            colors: [
                                runningColor.opacity(0.90 * gradientStrength),
                                runningColor.opacity(0.50 * gradientStrength),
                                runningColor.opacity(0.15 * gradientStrength),
                                .clear
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 220
                        )
                        .blur(radius: 12)
                        .offset(x: -18, y: -30)
                    }

                    if attentionCount > 0 {
                        RadialGradient(
                            colors: [
                                attentionColor.opacity(0.90 * gradientStrength),
                                attentionColor.opacity(0.50 * gradientStrength),
                                attentionColor.opacity(0.15 * gradientStrength),
                                .clear
                            ],
                            center: .topTrailing,
                            startRadius: 0,
                            endRadius: 220
                        )
                        .blur(radius: 12)
                        .offset(x: 18, y: -30)
                    }
                }
                .allowsHitTesting(false)
            }
            // Include the padded notch-safe space between the counters in the
            // button's hit target, not just the text and symbols.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var attentionStatus: AgentStatus? {
        let attentionAgents = store.agents.filter { $0.status.needsAttention }
        return attentionAgents
            .map(\.status)
            .sorted { $0.attentionPriority > $1.attentionPriority }
            .first
    }

    private var attentionSymbol: String {
        attentionStatus?.compactAttentionSymbol ?? "person.crop.circle.badge.questionmark"
    }

    private var attentionColor: Color {
        attentionCount > 0 ? (attentionStatus?.compactAttentionColor ?? .yellow) : .white.opacity(0.42)
    }

    /// Match the expanded row palette. If both sources are running, blue is
    /// used as the neutral shared accent; green remains reserved for done.
    private var runningColor: Color {
        let runningSources = Set(store.agents.filter { $0.status == .running }.map(\.source))
        if runningSources.contains(.codex) { return .blue }
        if runningSources.contains(.cursor) { return .purple }
        if runningSources.contains(.claude) { return .orange }
        return .blue
    }

    /// Kept as a named value so compact and expanded gradient tuning remains
    /// easy without changing the solid black base layer.
    private var gradientStrength: Double {
        1
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
        case .idle: "No agents"
        case .waiting: "Connecting"
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

private struct CountChip: View {
    let count: Int
    let label: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)

            Text("\(count)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.86)
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
