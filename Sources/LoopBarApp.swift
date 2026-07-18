import SwiftUI

@main
struct LoopBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("LoopBar", systemImage: "cursorarrow.rays") {
            MenuPanelView(store: appDelegate.store)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(store: appDelegate.store)
        }
        .defaultSize(width: 470, height: 300)
    }
}
