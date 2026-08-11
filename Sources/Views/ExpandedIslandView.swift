import SwiftUI

/// Expanded body driven by `IslandContent`.
struct ExpandedIslandView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var viewModel: IslandViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch viewModel.content {
            case .agents:
                agentsBody
                    .transition(paneTransition)
            case .settings:
                settingsBody
                    .transition(paneTransition)
            case .logs:
                logsBody
                    .transition(paneTransition)
            }
        }
        .clipped()
        .animation(paneAnimation, value: viewModel.content)
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
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .animation(listAnimation, value: store.agents)
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
        SettingsView(
            store: store,
            updater: .shared,
            onPrepareForUpdateCheck: viewModel.collapse,
            onDone: {
                withAnimation(paneAnimation) {
                    viewModel.selectContent(.agents)
                }
            }
        )
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

    private var paneTransition: AnyTransition {
        reduceMotion
            ? .identity
            : .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
    }

    private var paneAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    private var listAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }
}
