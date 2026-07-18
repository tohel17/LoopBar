import Foundation

@MainActor
final class Settings: ObservableObject {
    @Published var refreshSeconds: Double { didSet { defaults.set(refreshSeconds, forKey: Keys.refresh) } }
    private let defaults = UserDefaults.standard
    private enum Keys { static let refresh = "refreshSeconds" }

    init() {
        refreshSeconds = min(max(defaults.object(forKey: Keys.refresh) as? Double ?? 7, 5), 60)
    }
}
