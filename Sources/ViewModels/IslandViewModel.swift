import Combine
import Foundation

/// Owns island UI state: compact/expanded chrome, content pane, and hover flags.
///
/// Agent data remains in `AgentStore`; this view model only derives presentation state
/// and forwards user actions that affect the island chrome.
@MainActor
final class IslandViewModel: ObservableObject {
    @Published private(set) var state: IslandState = .compact
    @Published var content: IslandContent = .agents
    @Published private(set) var isHovered = false
    @Published private(set) var notificationMessage: String?

    private let store: AgentStore
    private var cancellables = Set<AnyCancellable>()
    private var collapseTask: Task<Void, Never>?
    private static let collapseDelaySeconds: TimeInterval = 2

    /// True when the panel should use expanded metrics and chrome.
    var isExpandedChrome: Bool { state.isExpandedChrome }

    init(store: AgentStore) {
        self.store = store
        observeStore()
    }

    // MARK: - User actions

    /// Toggle between compact and expanded chrome.
    func toggleExpanded() {
        if state.isExpandedChrome {
            collapseTask?.cancel()
            collapseTask = nil
            applyState(.compact)
            content = .agents
        } else {
            applyState(derivedExpandedState())
        }
    }

    /// Hover never expands. While expanded, cancel collapse on enter and
    /// schedule a 2s collapse after the pointer leaves.
    func setHovered(_ hovered: Bool) {
        isHovered = hovered
        guard state.isExpandedChrome else {
            collapseTask?.cancel()
            collapseTask = nil
            return
        }

        if hovered {
            collapseTask?.cancel()
            collapseTask = nil
            return
        }

        collapseTask?.cancel()
        collapseTask = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(Self.collapseDelaySeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self, !Task.isCancelled, !self.isHovered else { return }
            self.applyState(.compact)
            self.content = .agents
        }
    }

    func selectContent(_ content: IslandContent) {
        self.content = content
        if !state.isExpandedChrome {
            applyState(derivedExpandedState())
        }
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
