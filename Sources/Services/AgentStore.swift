import Foundation

@MainActor
final class AgentStore: ObservableObject {
    @Published private(set) var agents: [CursorAgent] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published var settings = Settings()
    private var pollingTask: Task<Void, Never>?

    init() { restartPolling() }
    deinit { pollingTask?.cancel() }
    func restartPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let seconds = self?.settings.refreshSeconds ?? 7
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }
    func refresh() async {
        do {
            let incoming = try await LocalCursorAgentAPI().fetchAgents()
                .sorted { $0.status.isTerminal == $1.status.isTerminal ? $0.title < $1.title : !$0.status.isTerminal }
            print("[LoopBar] displaying \(incoming.count) agents")
            agents = incoming; lastUpdated = .now; errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    func updateSettings() { restartPolling(); Task { await refresh() } }
}
