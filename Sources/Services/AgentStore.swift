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
    private var pollingTask: Task<Void, Never>?

    init() {
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

        do {
            incoming.append(contentsOf: try await cursorAPI.fetchAgents())
        } catch {
            errors.append("Cursor: \(error.localizedDescription)")
        }

        do {
            incoming.append(contentsOf: try await codexAPI.fetchAgents())
        } catch {
            errors.append("Codex: \(error.localizedDescription)")
        }

        lastUpdated = .now

        if !incoming.isEmpty {
            agents = incoming.sorted(by: sortAgents)
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
}
