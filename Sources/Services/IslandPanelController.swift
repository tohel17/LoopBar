import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandPanelController {
    private let store: AgentStore
    private var panel: NSPanel!
    private var hostingView: NSHostingView<IslandRootView>!
    private var expanded = false
    private var cancellables = Set<AnyCancellable>()

    init(store: AgentStore) {
        self.store = store
        setupPanel()
        reposition(animated: false)
        observeScreenChanges()
        observeContentChanges()
    }

    private func setupPanel() {
        let rootView = IslandRootView(
            store: store,
            expanded: Binding(
                get: { [weak self] in self?.expanded ?? false },
                set: { [weak self] in self?.setExpanded($0) }
            )
        )

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        hostingView = NSHostingView(rootView: rootView)
        panel.contentView = hostingView
    }

    private func setExpanded(_ expanded: Bool) {
        guard self.expanded != expanded else { return }
        self.expanded = expanded
        reposition(animated: true)
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reposition(animated: false)
            }
        }
    }

    private func observeContentChanges() {
        store.$agents
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.expanded else { return }
                self.reposition(animated: false)
            }
            .store(in: &cancellables)

        store.$errorMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.expanded else { return }
                self.reposition(animated: false)
            }
            .store(in: &cancellables)
    }

    private func reposition(animated: Bool) {
        guard let screen = targetScreen() else { return }

        let contentSize = IslandMetrics.size(
            expanded: expanded,
            agentCount: store.agents.count,
            hasError: store.errorMessage != nil
        )
        let frame = islandFrame(for: contentSize, on: screen)

        guard animated else {
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
        panel.orderFrontRegardless()
    }

    /// Prefer the built-in notched display; fall back to the main screen.
    private func targetScreen() -> NSScreen? {
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// Keeps the island fully inside the visible desktop area below the menu bar.
    private func islandFrame(for contentSize: CGSize, on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY
        let hasNotch = screen.safeAreaInsets.top > 0
        let size = NSSize(width: contentSize.width, height: contentSize.height)

        var x = screenFrame.midX - (size.width / 2)
        x = min(max(x, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)

        // Distance from the very top of the display
        let topInset: CGFloat = hasNotch ? 0 : 12

        // Position relative to the full screen instead of visibleFrame
        let y = screenFrame.maxY - size.height - topInset

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

private struct IslandRootView: View {
    @ObservedObject var store: AgentStore
    @Binding var expanded: Bool

    var body: some View {
        MenuPanelView(store: store, expanded: $expanded)
            .frame(
                width: expanded ? IslandMetrics.expandedWidth : IslandMetrics.compactWidth,
                height: IslandMetrics.contentHeight(
                    expanded: expanded,
                    agentCount: store.agents.count,
                    hasError: store.errorMessage != nil
                ) - (expanded ? IslandMetrics.expandedShadowPadding : IslandMetrics.compactShadowPadding),
                alignment: .top
            )
            .padding(.bottom, expanded ? IslandMetrics.expandedShadowPadding : IslandMetrics.compactShadowPadding)
    }
}
