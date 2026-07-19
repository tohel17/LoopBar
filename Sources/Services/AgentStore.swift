import Foundation

/// Observable store for Cursor agent data and polling lifecycle.
///
/// Deliberately free of island chrome / expand state — that lives in `IslandViewModel`.
@MainActor
final class AgentStore: ObservableObject {
    @Published private(set) var agents: [CursorAgent] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published var settings = Settings()

    private let cursorAPI = CursorAPI()
    private let codexAPI = CodexAPI()
    private let notificationService = NotificationService()
    private var pollingTask: Task<Void, Never>?
    private var hasLoadedInitialSnapshot = false
    private var lastStatuses: [String: AgentStatus] = [:]
    private var lastPublishedAgents: [String: CursorAgent] = [:]
    private var pendingCodexStatuses: [String: (status: AgentStatus, count: Int)] = [:]

    init() {
        notificationService.requestAuthorization()
        restartPolling()
    }

    deinit {
        pollingTask?.cancel()
    }

    func restartPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let seconds = max(self?.settings.refreshSeconds ?? 1, 1)
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    func refresh() async {
        var incoming: [CursorAgent] = []
        var errors: [String] = []

        if settings.cursorEnabled {
            do {
                incoming.append(contentsOf: try await cursorAPI.fetchAgents())
            } catch {
                errors.append("Cursor: \(error.localizedDescription)")
            }
        }

        if settings.codexEnabled {
            do {
                incoming.append(contentsOf: try await codexAPI.fetchAgents())
            } catch {
                // Codex can briefly lock, rotate, or delay its local SQLite state
                // when idle/backgrounded. Keep the last known Codex snapshot instead
                // of surfacing a noisy transient database error in the island.
                incoming.append(contentsOf: agents.filter { $0.source == .codex })
            }
        }

        lastUpdated = .now

        let sortedIncoming = incoming.sorted(by: sortAgents)
        let stabilizedIncoming = stabilizeTransientCodexStatuses(sortedIncoming)
        notifyStatusTransitions(for: stabilizedIncoming)

        if !stabilizedIncoming.isEmpty {
            agents = stabilizedIncoming
            errorMessage = errors.isEmpty ? nil : errors.joined(separator: " · ")
        } else {
            agents = []
            errorMessage = errors.isEmpty ? nil : errors.joined(separator: " · ")
        }
    }

    func updateSettings() {
        restartPolling()
        Task { await refresh() }
    }

    private func sortAgents(_ lhs: CursorAgent, _ rhs: CursorAgent) -> Bool {
        let leftPriority = statusPriority(lhs.status)
        let rightPriority = statusPriority(rhs.status)
        if leftPriority != rightPriority {
            return leftPriority < rightPriority
        }
        if lhs.status.isTerminal != rhs.status.isTerminal {
            return !lhs.status.isTerminal
        }
        switch (lhs.updatedAt, rhs.updatedAt) {
        case let (left?, right?):
            return left > right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            if lhs.source != rhs.source {
                return lhs.source.rawValue < rhs.source.rawValue
            }
            return lhs.title < rhs.title
        }
    }

    private func statusPriority(_ status: AgentStatus) -> Int {
        switch status {
        case .waitingForApproval, .waitingForInput, .blocked, .failed:
            return 0
        case .running:
            return 1
        case .queued:
            return 2
        case .unknown:
            return 3
        case .completed, .cancelled:
            return 4
        }
    }

    private func notifyStatusTransitions(for incoming: [CursorAgent]) {
        let incomingStatuses = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0.status) })
        defer {
            lastStatuses = incomingStatuses
            lastPublishedAgents = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
            hasLoadedInitialSnapshot = true
        }

        guard hasLoadedInitialSnapshot else { return }

        for agent in incoming {
            guard let oldStatus = lastStatuses[agent.id] else { continue }
            notificationService.notifyTransition(
                for: agent,
                from: oldStatus,
                to: agent.status,
                settings: settings
            )
        }
    }

    /// Codex can briefly persist an intermediate waiting marker while a tool
    /// call is still active. Require two consecutive polls before replacing a
    /// published running state with an attention state, avoiding UI flicker and
    /// false notifications without delaying real waiting states for long.
    private func stabilizeTransientCodexStatuses(_ incoming: [CursorAgent]) -> [CursorAgent] {
        incoming.map { agent in
            guard agent.source == .codex,
                  let previousStatus = lastStatuses[agent.id],
                  previousStatus == .running,
                  agent.status.needsAttention else {
                pendingCodexStatuses.removeValue(forKey: agent.id)
                return agent
            }

            let candidate = pendingCodexStatuses[agent.id]
            let nextCount = candidate?.status == agent.status ? (candidate?.count ?? 0) + 1 : 1
            pendingCodexStatuses[agent.id] = (agent.status, nextCount)

            guard nextCount < 2, let previousAgent = lastPublishedAgents[agent.id] else {
                pendingCodexStatuses.removeValue(forKey: agent.id)
                return agent
            }
            return previousAgent
        }
    }
}
