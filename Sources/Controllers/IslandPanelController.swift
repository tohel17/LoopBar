import AppKit
import Combine
import SwiftUI

/// AppKit host for the notch island.
///
/// Responsibilities are limited to creating the panel, hosting SwiftUI,
/// resizing/repositioning via `IslandGeometry`, and reacting to screen changes.
@MainActor
final class IslandPanelController {
    private let store: AgentStore
    private let viewModel: IslandViewModel
    private var panel: NSPanel!
    private var hostingView: NSHostingView<IslandRootView>!
    private var cancellables = Set<AnyCancellable>()
    private var lastExpandedChrome = false

    init(store: AgentStore, viewModel: IslandViewModel) {
        self.store = store
        self.viewModel = viewModel
        self.lastExpandedChrome = viewModel.isExpandedChrome
        setupPanel()
        reposition(animated: false)
        observeScreenChanges()
        observeSizeDrivers()
    }

    // MARK: - Panel setup

    private func setupPanel() {
        let rootView = IslandRootView(store: store, viewModel: viewModel)

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

    // MARK: - Observation

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

    /// Resize when island chrome or agent content that affects height changes.
    private func observeSizeDrivers() {
        viewModel.$state
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                let chrome = state.isExpandedChrome
                let animated = chrome != self.lastExpandedChrome
                self.lastExpandedChrome = chrome
                self.reposition(animated: animated)
            }
            .store(in: &cancellables)

        viewModel.$content
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.viewModel.isExpandedChrome else { return }
                self.reposition(animated: false)
            }
            .store(in: &cancellables)

        store.$agents
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.viewModel.isExpandedChrome else { return }
                self.reposition(animated: false)
            }
            .store(in: &cancellables)

        store.$errorMessage
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.viewModel.isExpandedChrome else { return }
                self.reposition(animated: false)
            }
            .store(in: &cancellables)
    }

    // MARK: - Positioning

    private func reposition(animated: Bool) {
        guard let screen = IslandGeometry.targetScreen() else { return }

        let contentSize = IslandMetrics.size(
            expanded: viewModel.isExpandedChrome,
            content: viewModel.content,
            agentCount: store.agents.count,
            hasError: store.errorMessage != nil
        )
        let frame = IslandGeometry.panelFrame(for: contentSize, on: screen)

        guard animated else {
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            return
        }

        viewModel.setAnimating(true)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.viewModel.setAnimating(false)
            }
        })
        panel.orderFrontRegardless()
    }
}
