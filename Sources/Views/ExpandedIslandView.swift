import SwiftUI

/// Expanded body driven by `IslandContent`.
struct ExpandedIslandView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        switch viewModel.content {
        case .agents:
            agentsBody
        case .settings:
            settingsBody
        case .logs:
            logsBody
        }
    }

    // MARK: - Agents

    private var agentsBody: some View {
        Group {
            if store.agents.isEmpty {
                ContentUnavailableView {
                    Label(
                        EmptyAgentsCopy.title(
                            lastUpdated: store.lastUpdated,
                            errorMessage: store.errorMessage
                        ),
                        systemImage: store.lastUpdated == nil ? "arrow.triangle.2.circlepath" : "bubble.left.and.bubble.right"
                    )
                } description: {
                    Text(
                        EmptyAgentsCopy.detail(
                            lastUpdated: store.lastUpdated,
                            errorMessage: store.errorMessage,
                            cursorEnabled: store.settings.cursorEnabled,
                            codexEnabled: store.settings.codexEnabled,
                            claudeEnabled: store.settings.claudeEnabled
                        )
                    )
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(store.agents) { agent in
                            AgentRowView(agent: agent)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                }
                .frame(height: IslandMetrics.listHeight(agentCount: store.agents.count))
            }

            if let error = store.errorMessage, !store.agents.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(.horizontal, 30)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Settings

    private var settingsBody: some View {
        SettingsView(store: store) {
            viewModel.selectContent(.agents)
        }
        .frame(maxWidth: .infinity)
        .frame(height: IslandMetrics.settingsBodyHeight)
    }

    // MARK: - Logs placeholder

    private var logsBody: some View {
        Text("Logs coming soon")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
    }
}
