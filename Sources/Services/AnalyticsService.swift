import FirebaseAnalytics
import FirebaseCore
import Foundation
import OSLog

/// Configures Firebase and records an active-installation event at launch and
/// once every 24 hours while LoopBar remains open.
@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    nonisolated static let heartbeatInterval: Duration = .seconds(24 * 60 * 60)

    private let logger = Logger(subsystem: "com.loopbar.app", category: "Analytics")
    private var isConfigured = false
    private var heartbeatTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard configureIfNeeded() else { return }
        Analytics.setAnalyticsCollectionEnabled(true)

        guard heartbeatTask == nil else { return }
        logActiveEvent()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.heartbeatInterval)
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                self?.logActiveEvent()
            }
        }
    }

    private func logActiveEvent() {
        Analytics.logEvent("app_active", parameters: [
            "app_version": AppVersion.current
        ])
    }

    private func configureIfNeeded() -> Bool {
        if isConfigured { return true }

        guard let configurationURL = Self.configurationURL,
              let options = FirebaseOptions(contentsOfFile: configurationURL.path) else {
            logger.error("Firebase configuration is unavailable; analytics will remain disabled.")
            return false
        }

        FirebaseApp.configure(options: options)
        isConfigured = true
        return true
    }

    private static var configurationURL: URL? {
        Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist")
            ?? Bundle.module.url(forResource: "GoogleService-Info", withExtension: "plist")
    }
}
