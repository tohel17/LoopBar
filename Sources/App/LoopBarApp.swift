import SwiftUI

@main
struct LoopBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        SwiftUI.Settings {
            SettingsView(store: appDelegate.store)
        }
    }
}
