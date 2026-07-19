import Foundation

@MainActor
final class Settings: ObservableObject {
    @Published var refreshSeconds: Double { didSet { defaults.set(refreshSeconds, forKey: Keys.refresh) } }
    @Published var cursorEnabled: Bool { didSet { defaults.set(cursorEnabled, forKey: Keys.cursorEnabled) } }
    @Published var codexEnabled: Bool { didSet { defaults.set(codexEnabled, forKey: Keys.codexEnabled) } }
    private let defaults = UserDefaults.standard
    private enum Keys {
        static let refresh = "refreshSeconds"
        static let cursorEnabled = "cursorMonitoringEnabled"
        static let codexEnabled = "codexMonitoringEnabled"
    }

    init() {
        refreshSeconds = min(max(defaults.object(forKey: Keys.refresh) as? Double ?? 1, 1), 60)
        cursorEnabled = defaults.object(forKey: Keys.cursorEnabled) as? Bool ?? true
        codexEnabled = defaults.object(forKey: Keys.codexEnabled) as? Bool ?? true
    }
}
