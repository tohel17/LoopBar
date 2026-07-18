import Combine
import Foundation

/// Owns island UI state: compact/expanded chrome, content pane, hover/animation flags.
///
/// Agent data remains in `AgentStore`; this view model only derives presentation state
/// and forwards user actions that affect the island chrome.
@MainActor
final class IslandViewModel: ObservableObject {
    @Published private(set) var state: IslandState = .compact
    @Published var content: IslandContent = .agents
    /// Reserved for future hover affordances; unused by views in this pass.
    @Published var isHovered = false
    @Published private(set) var isAnimating = false
    @Published private(set) var notificationMessage: String?

    private let store: AgentStore
    private var cancellables = Set<AnyCancellable>()

    /// True when the panel should use expanded metrics and chrome.
    var isExpandedChrome: Bool { state.isExpandedChrome }

    init(store: AgentStore) {
        self.store = store
        observeStore()
    }

    // MARK: - User actions

    /// Toggle between compact and expanded chrome (same spring as the previous binding).
    func toggleExpanded() {
        if state.isExpandedChrome {
            applyState(.compact)
            content = .agents
        } else {
            applyState(derivedExpandedState())
        }
    }

    func selectContent(_ content: IslandContent) {
        self.content = content
        if !state.isExpandedChrome {
            applyState(derivedExpandedState())
        }
    }

    func setHovered(_ hovered: Bool) {
        isHovered = hovered
    }

    /// Marks an AppKit panel resize animation as in-flight.
    func setAnimating(_ animating: Bool) {
        isAnimating = animating
    }

    // MARK: - Store observation

    private func observeStore() {
        store.$agents
            .combineLatest(store.$errorMessage, store.$lastUpdated)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.reconcileExpandedState()
            }
            .store(in: &cancellables)
    }

    /// When already expanded-like, remaps to loading / notification / expanded
    /// based on current store conditions without collapsing the island.
    private func reconcileExpandedState() {
        notificationMessage = store.errorMessage
        guard state.isExpandedChrome else { return }
        applyState(derivedExpandedState())
    }

    private func derivedExpandedState() -> IslandState {
        if store.errorMessage != nil {
            return .notification
        }
        // Connecting / first refresh with nothing to show yet.
        if store.agents.isEmpty && store.lastUpdated == nil {
            return .loading
        }
        return .expanded
    }

    private func applyState(_ newState: IslandState) {
        guard state != newState else { return }
        state = newState
    }
}
