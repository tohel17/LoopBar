import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = AgentStore()
    private(set) lazy var viewModel = IslandViewModel(store: store)
    private var islandController: IslandPanelController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard let existingInstance = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier != currentPID }) else {
            return
        }

        existingInstance.activate(options: [.activateAllWindows])
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        CursorHookCleanup.removeLegacyInstallation()
        if NotificationService.canUseUserNotifications {
            UNUserNotificationCenter.current().delegate = self
        }
        NSApp.setActivationPolicy(.accessory)
        islandController = IslandPanelController(store: store, viewModel: viewModel)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard
            let rawURL = response.notification.request.content.userInfo["agentURL"] as? String,
            let url = URL(string: rawURL)
        else {
            return
        }

        await MainActor.run {
            switch url.scheme {
            case "cursor":
                AgentOpener.open(url, source: .cursor)
            case "codex":
                AgentOpener.open(url, source: .codex)
            default:
                AgentOpener.open(url)
            }
        }
    }
}
