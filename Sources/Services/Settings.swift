import Foundation

@MainActor
final class Settings: ObservableObject {
    @Published var refreshSeconds: Double { didSet { defaults.set(refreshSeconds, forKey: Keys.refresh) } }
    @Published var cursorEnabled: Bool { didSet { defaults.set(cursorEnabled, forKey: Keys.cursorEnabled) } }
    @Published var codexEnabled: Bool { didSet { defaults.set(codexEnabled, forKey: Keys.codexEnabled) } }
    @Published var completionNotifications: Bool { didSet { defaults.set(completionNotifications, forKey: Keys.completionNotifications) } }
    @Published var attentionNotifications: Bool { didSet { defaults.set(attentionNotifications, forKey: Keys.attentionNotifications) } }
    @Published var failureNotifications: Bool { didSet { defaults.set(failureNotifications, forKey: Keys.failureNotifications) } }
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) } }
    private let defaults = UserDefaults.standard
    private enum Keys {
        static let refresh = "refreshSeconds"
        static let cursorEnabled = "cursorMonitoringEnabled"
        static let codexEnabled = "codexMonitoringEnabled"
        static let completionNotifications = "completionNotificationsEnabled"
        static let attentionNotifications = "attentionNotificationsEnabled"
        static let failureNotifications = "failureNotificationsEnabled"
        static let notificationsEnabled = "notificationsEnabled"
    }

    init() {
        refreshSeconds = min(max(defaults.object(forKey: Keys.refresh) as? Double ?? 1, 1), 60)
        cursorEnabled = defaults.object(forKey: Keys.cursorEnabled) as? Bool ?? true
        codexEnabled = defaults.object(forKey: Keys.codexEnabled) as? Bool ?? true
        completionNotifications = defaults.object(forKey: Keys.completionNotifications) as? Bool ?? true
        attentionNotifications = defaults.object(forKey: Keys.attentionNotifications) as? Bool ?? true
        failureNotifications = defaults.object(forKey: Keys.failureNotifications) as? Bool ?? true
        notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
    }
}
