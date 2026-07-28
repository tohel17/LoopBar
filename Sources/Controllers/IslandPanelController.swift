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
    private var outsideClickMonitors: [Any] = []
    private var lastExpandedChrome = false

    init(store: AgentStore, viewModel: IslandViewModel) {
        self.store = store
        self.viewModel = viewModel
        self.lastExpandedChrome = viewModel.isExpandedChrome
        setupPanel()
        reposition(animated: false)
        observeScreenChanges()
        observeSizeDrivers()
        observeOutsideClicks()
    }

    deinit {
        outsideClickMonitors.forEach(NSEvent.removeMonitor)
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

    /// Collapse without consuming the original click. Local monitoring covers
    /// LoopBar-owned windows; global monitoring covers clicks in other apps.
    private func observeOutsideClicks() {
        let mouseDownEvents: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]

        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDownEvents) { [weak self] event in
            let screenLocation = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.handleOutsideClick(at: screenLocation)
            }
            return event
        } {
            outsideClickMonitors.append(localMonitor)
        }

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDownEvents) { [weak self] _ in
            let screenLocation = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.handleOutsideClick(at: screenLocation)
            }
        } {
            outsideClickMonitors.append(globalMonitor)
        }
    }

    private func handleOutsideClick(at screenLocation: CGPoint) {
        guard Self.shouldCollapseOnOutsideClick(
            isExpanded: viewModel.isExpandedChrome,
            panelFrame: panel.frame,
            clickLocation: screenLocation
        ) else {
            return
        }
        viewModel.collapse()
    }

    static func shouldCollapseOnOutsideClick(
        isExpanded: Bool,
        panelFrame: CGRect,
        clickLocation: CGPoint
    ) -> Bool {
        isExpanded && !panelFrame.contains(clickLocation)
    }

    /// Resize when island chrome or agent content that affects height changes.
    private func observeSizeDrivers() {
        viewModel.$state
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                let expandedChrome = state.isExpandedChrome
                let animated = expandedChrome != self.lastExpandedChrome
                self.lastExpandedChrome = expandedChrome
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

        if animated {
            let currentFrame = panel.frame
            let startWidth = currentFrame.width > 0 ? currentFrame.width : frame.width
            let startFrame = CGRect(
                x: frame.midX - (startWidth / 2),
                y: frame.minY,
                width: startWidth,
                height: frame.height
            )

            // Keep the island glued to the notch: snap vertical changes immediately,
            // then animate only the horizontal expansion/collapse.
            panel.setFrame(startFrame, display: true)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        panel.orderFrontRegardless()
    }
}
