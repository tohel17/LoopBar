import Foundation
import OSLog
import UserNotifications

@MainActor
final class NotificationService {
    enum PermissionStatus: Equatable {
        case checking
        case notRequested
        case allowed
        case denied
        case alertsDisabled
        case unavailable(String)
    }

    enum TestResult: Equatable {
        case delivered
        case denied
        case alertsDisabled
        case failed(String)

        var isSuccess: Bool {
            self == .delivered
        }
    }

    static var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private let logger = Logger(subsystem: "com.loopbar.app", category: "notifications")
    private var isAuthorized = false
    private var authorizationResolved = false
    private var pendingNotifications: [(agent: CursorAgent, status: AgentStatus)] = []

    func refreshAuthorizationStatus() async -> PermissionStatus {
        guard Self.canUseUserNotifications else {
            // SwiftPM/Xcode debug runs can launch LoopBar as a raw executable
            // from DerivedData instead of a real .app bundle. UserNotifications
            // crashes in that mode because the process has no bundle proxy, so
            // debug builds use the osascript fallback in `notifyTransition`.
            isAuthorized = true
            authorizationResolved = true
            return .unavailable("Notification permission is only available in the packaged app.")
        }

        let status = await permissionStatus(using: .current())
        switch status {
        case .allowed:
            updateAuthorizationState(isAuthorized: true)
        case .checking:
            break
        case .notRequested, .denied, .alertsDisabled, .unavailable:
            updateAuthorizationState(isAuthorized: false)
        }
        return status
    }

    func sendTestNotification() async -> TestResult {
        guard Self.canUseUserNotifications else {
            return .failed("Launch the packaged LoopBar.app to test macOS notifications.")
        }

        let center = UNUserNotificationCenter.current()

        do {
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    updateAuthorizationState(isAuthorized: false)
                    return .denied
                }
                settings = await center.notificationSettings()
            }

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                updateAuthorizationState(isAuthorized: true)
            case .denied:
                updateAuthorizationState(isAuthorized: false)
                return .denied
            case .notDetermined:
                updateAuthorizationState(isAuthorized: false)
                return .failed("macOS did not resolve notification permission.")
            @unknown default:
                updateAuthorizationState(isAuthorized: false)
                return .failed("macOS returned an unknown authorization state.")
            }

            guard settings.alertSetting == .enabled else {
                return .alertsDisabled
            }

            try await deliverTestNotification(using: center)
            return .delivered
        } catch {
            logger.error("Test notification failed: \(error.localizedDescription, privacy: .public)")
            return .failed(Self.describe(error))
        }
    }

    private func permissionStatus(using center: UNUserNotificationCenter) async -> PermissionStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notRequested
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return settings.alertSetting == .enabled ? .allowed : .alertsDisabled
        @unknown default:
            return .unavailable("macOS returned an unknown notification permission state.")
        }
    }

    func notifyTransition(
        for agent: CursorAgent,
        from oldStatus: AgentStatus,
        to newStatus: AgentStatus,
        settings: Settings
    ) {
        guard shouldNotify(from: oldStatus, to: newStatus, settings: settings) else { return }

        guard authorizationResolved else {
            pendingNotifications.append((agent, newStatus))
            return
        }
        guard isAuthorized else { return }

        deliver(agent: agent, status: newStatus)
    }

    private func updateAuthorizationState(isAuthorized authorized: Bool) {
        isAuthorized = authorized
        authorizationResolved = true
        if authorized {
            flushPendingNotifications()
        } else {
            pendingNotifications.removeAll()
        }
    }

    private func flushPendingNotifications() {
        guard isAuthorized else {
            pendingNotifications.removeAll()
            return
        }
        let pending = pendingNotifications
        pendingNotifications.removeAll()
        for notification in pending {
            deliver(agent: notification.agent, status: notification.status)
        }
    }

    private func deliverTestNotification(using center: UNUserNotificationCenter) async throws {
        let content = Self.makeTestContent()
        let request = UNNotificationRequest(
            identifier: "loopbar.test-icon.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }

    static func makeTestContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "LoopBar notification test"
        content.body = "The LoopBar logo should appear on the left."
        content.sound = .default
        return content
    }

    private func deliver(agent: CursorAgent, status newStatus: AgentStatus) {

        if !Self.canUseUserNotifications {
            deliverDebugNotification(title: notificationTitle(for: agent, status: newStatus), body: agent.latestStatus)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = notificationTitle(for: agent, status: newStatus)
        content.body = agent.latestStatus
        content.sound = .default
        content.threadIdentifier = agent.id
        if let url = agent.url {
            content.userInfo = [
                "agentURL": url.absoluteString,
                "agentSource": agent.source.rawValue
            ]
        } else {
            content.userInfo = ["agentSource": agent.source.rawValue]
        }
        // Do not use an image attachment for branding: macOS renders attachments
        // on the right. The left source icon comes from the registered app bundle.

        let request = UNNotificationRequest(
            identifier: "loopbar.\(agent.id).\(newStatus.rawValue)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [logger] error in
            if let error {
                logger.error("Agent notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func deliverDebugNotification(title: String, body: String) {
        let script = """
        display notification "\(Self.appleScriptEscaped(body))" with title "\(Self.appleScriptEscaped(title))" sound name "Glass"
        """

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
        }
    }

    private static func appleScriptEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == UNErrorDomain {
            return "\(nsError.localizedDescription) (UNError \(nsError.code))"
        }
        return nsError.localizedDescription
    }

    private func shouldNotify(from oldStatus: AgentStatus, to newStatus: AgentStatus, settings: Settings) -> Bool {
        guard oldStatus != newStatus else { return false }
        guard settings.notificationsEnabled else { return false }

        if newStatus == .completed, !oldStatus.isTerminal {
            return settings.completionNotifications
        }
        if newStatus == .failed, oldStatus != .failed {
            return settings.failureNotifications
        }
        if newStatus.needsAttention, !oldStatus.needsAttention {
            return settings.attentionNotifications
        }
        return false
    }

    private func notificationTitle(for agent: CursorAgent, status: AgentStatus) -> String {
        switch status {
        case .completed:
            return "\(agent.source.rawValue) completed: \(agent.title)"
        case .waitingForApproval:
            return "\(agent.source.rawValue) needs approval"
        case .waitingForInput:
            return "\(agent.source.rawValue) is waiting for you"
        case .blocked:
            return "\(agent.source.rawValue) is blocked"
        case .failed:
            return "\(agent.source.rawValue) failed"
        default:
            return "\(agent.source.rawValue): \(agent.title)"
        }
    }
}
