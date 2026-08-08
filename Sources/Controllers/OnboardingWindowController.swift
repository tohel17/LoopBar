import AppKit
import SwiftUI

/// Hosts the one-time setup assistant without adding a persistent app window.
@MainActor
final class OnboardingWindowController: NSWindowController {
    init(store: AgentStore, onComplete: @escaping () -> Void) {
        let rootView = OnboardingView(
            settings: store.settings,
            launchAtLogin: store.launchAtLogin,
            onComplete: onComplete
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 570),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Welcome to LoopBar"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.contentView = NSHostingView(rootView: rootView)

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let window else { return }
        window.center()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
