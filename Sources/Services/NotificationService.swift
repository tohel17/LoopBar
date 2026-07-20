import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    static var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private var isAuthorized = false
    private var authorizationResolved = false
    private var pendingNotifications: [(agent: CursorAgent, status: AgentStatus)] = []

    func requestAuthorization() {
        guard Self.canUseUserNotifications else {
            // SwiftPM/Xcode debug runs can launch LoopBar as a raw executable
            // from DerivedData instead of a real .app bundle. UserNotifications
            // crashes in that mode because the process has no bundle proxy, so
            // debug builds use the osascript fallback in `notifyTransition`.
            isAuthorized = true
            authorizationResolved = true
            return
        }

        Task {
            do {
                isAuthorized = try await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .sound]
                )
                authorizationResolved = true
                flushPendingNotifications()
            } catch {
                isAuthorized = false
                authorizationResolved = true
                pendingNotifications.removeAll()
            }
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
            content.userInfo = ["agentURL": url.absoluteString]
        }

        let request = UNNotificationRequest(
            identifier: "loopbar.\(agent.id).\(newStatus.rawValue)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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
