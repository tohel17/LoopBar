import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = AgentStore()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
