import SwiftUI

/// Top-level SwiftUI host embedded in the AppKit panel.
struct IslandRootView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var viewModel: IslandViewModel

    private var expanded: Bool { viewModel.isExpandedChrome }

    var body: some View {
        MenuPanelView(store: store, viewModel: viewModel)
            .frame(
                width: expanded ? IslandMetrics.expandedWidth : IslandMetrics.compactWidth,
                height: IslandMetrics.contentHeight(
                    expanded: expanded,
                    content: viewModel.content,
                    agentCount: store.agents.count,
                    hasError: store.errorMessage != nil
                ) - IslandMetrics.shadowPadding(expanded: expanded),
                alignment: .top
            )
            .padding(.bottom, IslandMetrics.shadowPadding(expanded: expanded))
    }
}
