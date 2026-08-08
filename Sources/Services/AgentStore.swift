import AppKit
import Combine
import Foundation

/// Observable store for event-triggered and periodically reconciled agent data.
///
/// Deliberately free of island chrome / expand state — that lives in `IslandViewModel`.
@MainActor
final class AgentStore: ObservableObject {
    @Published private(set) var agents: [CursorAgent] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var notificationPermissionStatus: NotificationService.PermissionStatus = .checking
    @Published var settings = Settings()

    private let cursorAPI = CursorAPI()
    private let codexAPI = CodexAPI()
    private let claudeAPI = ClaudeAPI()
    private let cursorFileWatcher = CursorFileWatcher()
    private let notificationService = NotificationService()
    private var pollingTask: Task<Void, Never>?
    private var hasStartedMonitoring = false
    private var isRefreshing = false
    private var refreshPending = false
    private var hasLoadedInitialSnapshot = false
    private var lastStatuses: [String: AgentStatus] = [:]
    private var settingsObserver: AnyCancellable?

    init() {
        // `settings` is a nested ObservableObject, so mutating one of its
        // properties never reaches AgentStore's own publisher. Without this
        // forwarding, controls bound through `$store.settings.…` keep rendering
        // the previous value even though the write landed.
        settingsObserver = settings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        guard settings.hasCompletedOnboarding else { return }
        startMonitoring()
        restartPolling()
    }

    private func startMonitoring() {
        guard !hasStartedMonitoring else { return }
        hasStartedMonitoring = true
        cursorFileWatcher.start { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.settings.cursorEnabled else { return }
                await self.refresh()
            }
        }
    }

    func refreshNotificationAuthorization() {
        Task { [weak self] in
            guard let self else { return }
            notificationPermissionStatus = await notificationService.refreshAuthorizationStatus()
        }
    }

    deinit {
        pollingTask?.cancel()
        cursorFileWatcher.stop()
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
        if isRefreshing {
            refreshPending = true
            return
        }

        isRefreshing = true
        repeat {
            refreshPending = false
            await performRefresh()
        } while refreshPending
        isRefreshing = false
    }

    private func performRefresh() async {
        var incoming: [CursorAgent] = []
        var errors: [String] = []

        if settings.cursorEnabled {
            do {
                incoming.append(contentsOf: try await cursorAPI.fetchAgents())
            } catch {
                errors.append("Cursor: \(error.localizedDescription)")
                // File events can arrive while Cursor is between SQLite WAL
                // writes. Keep the previous snapshot until the recovery pass
                // can read a consistent database view.
                incoming.append(contentsOf: agents.filter { $0.source == .cursor })
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

        if settings.claudeEnabled {
            do {
                incoming.append(contentsOf: try await claudeAPI.fetchAgents())
            } catch {
                // Process inspection can fail transiently while the terminal
                // changes state. Preserve the prior Claude snapshot instead
                // of falsely completing every visible session.
                incoming.append(contentsOf: agents.filter { $0.source == .claude })
            }
        }

        lastUpdated = .now

        let sortedIncoming = incoming.sorted(by: sortAgents)
        notifyStatusTransitions(for: sortedIncoming)

        if !sortedIncoming.isEmpty {
            agents = sortedIncoming
            errorMessage = errors.isEmpty ? nil : errors.joined(separator: " · ")
        } else {
            agents = []
            errorMessage = errors.isEmpty ? nil : errors.joined(separator: " · ")
        }
    }

    func updateSettings() {
        guard settings.hasCompletedOnboarding else { return }
        startMonitoring()
        restartPolling()
        Task { await refresh() }
    }

    func completeOnboarding() async {
        if settings.notificationsEnabled {
            notificationPermissionStatus = await notificationService.requestAuthorization()
        } else {
            notificationPermissionStatus = await notificationService.refreshAuthorizationStatus()
        }
        settings.completeOnboarding()
        updateSettings()
    }

    func requestNotificationAuthorization() {
        notificationPermissionStatus = .checking
        Task { [weak self] in
            guard let self else { return }
            notificationPermissionStatus = await notificationService.requestAuthorization()
        }
    }

    func openNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
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

}
