import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject private var launchAtLogin: LaunchAtLoginService
    @ObservedObject private var updater: AppUpdater
    /// When embedded in the island, dismiss returns to the agents pane.
    var onDone: (() -> Void)?
    /// Lets the island collapse before Sparkle presents its own window.
    var onPrepareForUpdateCheck: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var advancedExpanded = false

    private let refreshOptions: [Double] = [1, 2, 5, 6, 10, 15, 30, 60]

    private var isEmbedded: Bool { onDone != nil }

    init(
        store: AgentStore,
        updater: AppUpdater,
        onPrepareForUpdateCheck: (() -> Void)? = nil,
        onDone: (() -> Void)? = nil
    ) {
        self.store = store
        self.onDone = onDone
        self.onPrepareForUpdateCheck = onPrepareForUpdateCheck
        _launchAtLogin = ObservedObject(wrappedValue: store.launchAtLogin)
        _updater = ObservedObject(wrappedValue: updater)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.vertical, showsIndicators: false) {
                settingsOverview
                    .padding(.bottom, 2)
            }

            if isEmbedded {
                Button(action: finish) {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, isEmbedded ? 38 : 20)
        .padding(.vertical, isEmbedded ? 20 : 18)
        .frame(width: isEmbedded ? nil : 440)
        .frame(minHeight: isEmbedded ? nil : 500)
        .navigationTitle("LoopBar settings")
        .toolbar {
            if !isEmbedded {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }
                }
            }
        }
        // Apply polling changes immediately instead of waiting for the current
        // interval to elapse.
        .onChange(of: store.settings.refreshSeconds) { _, _ in store.updateSettings() }
        .onChange(of: store.settings.notificationsEnabled) { _, enabled in
            if enabled {
                store.requestNotificationAuthorization()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
            store.refreshNotificationAuthorization()
        }
        .onAppear {
            store.refreshNotificationAuthorization()
        }
    }

    private var settingsOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Settings")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Choose what LoopBar watches and when it gets your attention.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            settingsCard(
                title: "Monitored apps",
                subtitle: "Show activity from these local tools",
                symbol: "rectangle.3.group.fill",
                color: .purple
            ) {
                sourceToggle(
                    title: "Cursor",
                    subtitle: "Composer activity",
                    icon: "cursorarrow.rays",
                    color: .purple,
                    isOn: $store.settings.cursorEnabled
                )
                settingDivider
                sourceToggle(
                    title: "Codex",
                    subtitle: "Task activity",
                    icon: "sparkles",
                    color: .blue,
                    isOn: $store.settings.codexEnabled
                )
                settingDivider
                sourceToggle(
                    title: "Claude Code",
                    subtitle: "Terminal session activity",
                    icon: "sparkle",
                    color: .claudeRunning,
                    isOn: $store.settings.claudeEnabled
                )
            }

            settingsCard(
                title: "App behavior",
                subtitle: "The controls you are most likely to change",
                symbol: "switch.2",
                color: .green
            ) {
                trailingPreferenceToggle(
                    title: "Launch at login",
                    subtitle: "Start LoopBar automatically",
                    icon: "power",
                    color: .green,
                    isOn: launchAtLoginBinding
                )
                .disabled(!launchAtLogin.isAvailable)

                launchAtLoginGuidance
                settingDivider

                trailingPreferenceToggle(
                    title: "Notifications",
                    subtitle: "Alert me when work needs attention",
                    icon: "bell.fill",
                    color: .blue,
                    isOn: $store.settings.notificationsEnabled
                )

                if store.settings.notificationsEnabled {
                    permissionGuidance
                }

                settingDivider

                trailingPreferenceToggle(
                    title: "Automatic updates",
                    subtitle: "Download new versions in the background",
                    icon: "arrow.triangle.2.circlepath",
                    color: .green,
                    isOn: automaticUpdatesBinding
                )
                .disabled(!updater.isAvailable || !updater.isInstalledInApplications)

                HStack {
                    Text(updater.availabilityMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 12)

                    Button("Check for Updates…", action: checkForUpdates)
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.link)
                    .disabled(!updater.isAvailable)
                }
                .padding(.leading, 38)
            }

            advancedSettings
        }
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(disclosureAnimation) {
                    advancedExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.primary.opacity(0.055), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Advanced")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Refresh timing and notification types")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(advancedExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(advancedExpanded ? "Collapse advanced settings" : "Expand advanced settings")

            if advancedExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    settingDivider

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Refresh interval")
                                .font(.system(size: 12, weight: .semibold))
                            Text("How often LoopBar checks for changes")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Picker("Refresh interval", selection: $store.settings.refreshSeconds) {
                            ForEach(refreshOptions, id: \.self) { seconds in
                                Text(seconds < 60 ? "\(Int(seconds)) sec" : "1 min")
                                    .tag(seconds)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                    }

                    if store.settings.notificationsEnabled {
                        settingDivider

                        VStack(alignment: .leading, spacing: 9) {
                            Text("Notify me when")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)

                            compactToggle(
                                title: "Work completes",
                                icon: "checkmark.circle.fill",
                                color: .green,
                                isOn: $store.settings.completionNotifications
                            )
                            compactToggle(
                                title: "Work needs attention",
                                icon: "hand.raised.fill",
                                color: .yellow,
                                isOn: $store.settings.attentionNotifications
                            )
                            compactToggle(
                                title: "Work fails",
                                icon: "xmark.octagon.fill",
                                color: .red,
                                isOn: $store.settings.failureNotifications
                            )
                        }
                    }
                }
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.8)
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String,
        symbol: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(12)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.8)
        }
    }

    private func sourceToggle(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        trailingPreferenceToggle(
            title: title,
            subtitle: subtitle,
            icon: icon,
            color: color,
            isOn: isOn
        )
        .onChange(of: isOn.wrappedValue) { _, _ in store.updateSettings() }
    }

    private func trailingPreferenceToggle(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            preferenceLabel(title: title, subtitle: subtitle, icon: icon, color: color)

            Spacer(minLength: 16)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity)
    }

    private func preferenceLabel(
        title: String,
        subtitle: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func compactToggle(
        title: String,
        icon: String,
        color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Label {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }

            Spacer(minLength: 16)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity)
    }

    private var settingDivider: some View {
        Divider()
            .overlay(.primary.opacity(0.07))
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
    }

    private var automaticUpdatesBinding: Binding<Bool> {
        Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        )
    }

    @ViewBuilder
    private var launchAtLoginGuidance: some View {
        if let message = launchAtLoginMessage {
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(launchAtLogin.errorMessage == nil ? Color.secondary : Color.red)
                if launchAtLogin.requiresApproval {
                    Button("Open Login Items Settings") {
                        launchAtLogin.openLoginItemsSettings()
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.link)
                }
            }
            .padding(.leading, 38)
        }
    }

    private var launchAtLoginMessage: String? {
        if let error = launchAtLogin.errorMessage {
            return error
        }
        if launchAtLogin.requiresApproval {
            return "macOS requires approval before LoopBar can launch at login."
        }
        return launchAtLogin.availabilityMessage
    }

    @ViewBuilder
    private var permissionGuidance: some View {
        switch store.notificationPermissionStatus {
        case .denied:
            permissionCard(
                title: "Notifications are turned off",
                message: "Allow LoopBar notifications in System Settings.",
                symbol: "bell.slash.fill",
                color: .orange,
                actionTitle: "Open System Settings",
                action: store.openNotificationSettings
            )
        case .alertsDisabled:
            permissionCard(
                title: "Notification banners are off",
                message: "Choose Banners for LoopBar in System Settings.",
                symbol: "rectangle.on.rectangle.slash.fill",
                color: .orange,
                actionTitle: "Open System Settings",
                action: store.openNotificationSettings
            )
        case .notRequested:
            permissionCard(
                title: "Permission required",
                message: "Allow LoopBar to show agent updates.",
                symbol: "bell.badge.fill",
                color: .blue,
                actionTitle: "Allow notifications",
                action: store.requestNotificationAuthorization
            )
        case let .unavailable(message):
            permissionCard(
                title: "Notifications unavailable",
                message: message,
                symbol: "exclamationmark.triangle.fill",
                color: .orange
            )
        case .checking, .allowed:
            EmptyView()
        }
    }

    private func permissionCard(
        title: String,
        message: String,
        symbol: String,
        color: Color,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.link)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(color.opacity(0.16), lineWidth: 0.8)
        }
        .padding(.top, 2)
    }

    private var disclosureAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    private func checkForUpdates() {
        let waitsForCollapse = onPrepareForUpdateCheck != nil && !reduceMotion
        onPrepareForUpdateCheck?()

        Task { @MainActor [updater] in
            if waitsForCollapse {
                try? await Task.sleep(nanoseconds: 250_000_000)
            } else {
                await Task.yield()
            }
            updater.checkForUpdates()
        }
    }

    private func finish() {
        store.updateSettings()
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }
}
