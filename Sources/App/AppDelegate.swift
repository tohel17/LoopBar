import AppKit
import CoreServices
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = AgentStore()
    private(set) lazy var viewModel = IslandViewModel(store: store)
    private var islandController: IslandPanelController?
    private var onboardingController: OnboardingWindowController?

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
        registerBundleIcon()
        if NotificationService.canUseUserNotifications {
            UNUserNotificationCenter.current().delegate = self
        }
        NSApp.setActivationPolicy(.accessory)
        islandController = IslandPanelController(store: store, viewModel: viewModel)
        showOnboardingIfNeeded()

        if CommandLine.arguments.contains("--test-notification") {
            sendTestNotification()
        }
    }

    private func showOnboardingIfNeeded() {
        guard !store.settings.hasCompletedOnboarding else { return }

        let controller = OnboardingWindowController(settings: store.settings) { [weak self] in
            guard let self else { return }
            self.store.completeOnboarding()
            self.onboardingController?.close()
            self.onboardingController = nil
        }
        onboardingController = controller
        controller.present()
    }

    /// One-shot banner so we can verify the LEFT app icon without waiting for an agent.
    private func sendTestNotification() {
        guard NotificationService.canUseUserNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = "LoopBar icon check"
        content.body = "Left icon should be the LoopBar logo (not the grid placeholder)."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "loopbar.test-icon.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Ensure Launch Services / Notification Center can resolve LoopBar's logo
    /// for the LEFT notification icon (not a UNNotificationAttachment).
    private func registerBundleIcon() {
        if let icns = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: icns) {
            NSApp.applicationIconImage = image
        } else if let named = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = named
        }

        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
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
        let userInfo = response.notification.request.content.userInfo
        let rawURL = userInfo["agentURL"] as? String
        let rawSource = userInfo["agentSource"] as? String

        guard let target = NotificationOpenTarget.resolve(agentURL: rawURL, agentSource: rawSource) else {
            return
        }

        await MainActor.run {
            AgentOpener.open(target.url, source: target.source)
        }
    }
}
