import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = AgentStore()
    private var islandController: IslandPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        islandController = IslandPanelController(store: store)
    }
}
