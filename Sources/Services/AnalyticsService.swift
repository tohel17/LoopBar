import FirebaseAnalytics
import FirebaseCore
import Foundation
import OSLog

/// Configures Firebase and records one active-installation event per launch.
@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    private let logger = Logger(subsystem: "com.loopbar.app", category: "Analytics")
    private var isConfigured = false
    private var didLogActiveEvent = false

    private init() {}

    func start() {
        guard configureIfNeeded() else { return }
        Analytics.setAnalyticsCollectionEnabled(true)

        guard !didLogActiveEvent else { return }
        didLogActiveEvent = true
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
