import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AgentStore
    /// When embedded in the island, dismiss returns to the agents pane.
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var notificationsExpanded = true

    private let refreshOptions: [Double] = [1, 2, 5, 6, 10, 15, 30, 60]

    private var isEmbedded: Bool { onDone != nil }

    init(store: AgentStore, onDone: (() -> Void)? = nil) {
        self.store = store
        self.onDone = onDone
    }

    var body: some View {
        Group {
            if isEmbedded {
                embeddedContent
            } else {
                Form {
                    settingsContent
                }
            }
        }
        // Both layouts expose the interval picker; restart polling so a new
        // interval applies now instead of after the in-flight sleep elapses.
        .onChange(of: store.settings.refreshSeconds) { _, _ in store.updateSettings() }
        .padding(.horizontal, isEmbedded ? 38 : 16)
        .padding(.vertical, isEmbedded ? 22 : 16)
        .frame(width: isEmbedded ? nil : 420)
        .navigationTitle("LoopBar settings")
        .toolbar {
            if !isEmbedded {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }
                }
            }
        }
    }

    private var embeddedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.vertical, showsIndicators: false) {
                embeddedSettingsSections
                    .padding(.bottom, 2)
            }

            Button(action: finish) {
                Text("Done")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var embeddedSettingsSections: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.purple)
                    .frame(width: 30, height: 30)
                    .background(.purple.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local agents")
                        .font(.system(size: 15, weight: .bold))
                    Text("Monitors Cursor, Codex, and Claude Code")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.52))
                }
                Spacer()
                Text("v\(AppVersion.current)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.52))
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Refresh interval")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Picker("Refresh interval", selection: $store.settings.refreshSeconds) {
                        ForEach(refreshOptions, id: \.self) { seconds in
                            Text(seconds < 60 ? "\(Int(seconds)) sec" : "1 min")
                                .tag(seconds)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            sourceToggles

            notificationPreferences
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        Section("Local agents") {
            Text("Monitoring your three most recently updated Cursor composers and Codex tasks.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Version", value: AppVersion.current)
        }
        Section("Refresh") {
            Picker("Refresh interval", selection: $store.settings.refreshSeconds) {
                ForEach(refreshOptions, id: \.self) { seconds in
                    Text(seconds < 60 ? "\(Int(seconds)) seconds" : "1 minute")
                        .tag(seconds)
                }
            }
            .pickerStyle(.menu)
        }
        Section("Sources") {
            Toggle("Monitor Cursor", isOn: $store.settings.cursorEnabled)
            Toggle("Monitor Codex", isOn: $store.settings.codexEnabled)
            Toggle("Monitor Claude Code", isOn: $store.settings.claudeEnabled)
            Text("Disabled sources are not polled and do not produce errors or notifications.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        Section("Notifications") {
            Toggle("Enable notifications", isOn: $store.settings.notificationsEnabled)
            if store.settings.notificationsEnabled {
                DisclosureGroup("Notification types", isExpanded: $notificationsExpanded) {
                    Toggle("Completion notifications", isOn: $store.settings.completionNotifications)
                    Toggle("Needs-attention notifications", isOn: $store.settings.attentionNotifications)
                    Toggle("Failure notifications", isOn: $store.settings.failureNotifications)
                }
                permissionGuidance(embedded: false)
                formTestNotificationButton
            }
            if !store.settings.notificationsEnabled {
                Text("Notification options are hidden while notifications are disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .onAppear { store.refreshNotificationAuthorization() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshNotificationAuthorization()
        }
    }

    private var sourceToggles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sources")
                .font(.system(size: 12, weight: .medium))
            sourceToggle(
                title: "Cursor",
                subtitle: "Composer activity",
                icon: "cursorarrow.rays",
                color: .purple,
                isOn: $store.settings.cursorEnabled
            )
            sourceToggle(
                title: "Codex",
                subtitle: "Task activity",
                icon: "sparkles",
                color: .blue,
                isOn: $store.settings.codexEnabled
            )
            sourceToggle(
                title: "Claude Code",
                subtitle: "Terminal session activity",
                icon: "sparkle",
                color: .orange,
                isOn: $store.settings.claudeEnabled
            )
            Text("Disabled sources are not polled or shown in LoopBar.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.48))
        }
        .toggleStyle(.switch)
        .onChange(of: store.settings.cursorEnabled) { _, _ in store.updateSettings() }
        .onChange(of: store.settings.codexEnabled) { _, _ in store.updateSettings() }
        .onChange(of: store.settings.claudeEnabled) { _, _ in store.updateSettings() }
    }

    private var notificationPreferences: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Notifications")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Toggle("", isOn: $store.settings.notificationsEnabled)
                    .labelsHidden()
            }
            .contentShape(Rectangle())

            if store.settings.notificationsEnabled {
                permissionGuidance(embedded: true)

                DisclosureGroup("Notification types", isExpanded: $notificationsExpanded) {
                    VStack(alignment: .leading, spacing: 6) {
                        preferenceToggle(
                            title: "Completed work",
                            subtitle: "",
                            icon: "checkmark.circle.fill",
                            color: .green,
                            isOn: $store.settings.completionNotifications
                        )
                        preferenceToggle(
                            title: "Needs your attention",
                            subtitle: "",
                            icon: "hand.raised.fill",
                            color: .yellow,
                            isOn: $store.settings.attentionNotifications
                        )
                        preferenceToggle(
                            title: "Failures",
                            subtitle: "",
                            icon: "xmark.octagon.fill",
                            color: .red,
                            isOn: $store.settings.failureNotifications
                        )
                    }
                }

                embeddedTestNotificationButton
            } else {
                Text("Notification options are hidden while disabled.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
        .toggleStyle(.switch)
        .onAppear { store.refreshNotificationAuthorization() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshNotificationAuthorization()
        }
    }

    private var formTestNotificationButton: some View {
        Button {
            store.sendTestNotification()
        } label: {
            HStack {
                Label("Test notification", systemImage: "bell.badge")
                Spacer()
                notificationTestAccessory
            }
        }
        .disabled(store.isSendingTestNotification)
    }

    private var embeddedTestNotificationButton: some View {
        Button {
            store.sendTestNotification()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 28, height: 28)
                    .background(.blue.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Test notification")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Send a sample LoopBar alert")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.48))
                }

                Spacer(minLength: 8)
                notificationTestAccessory
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(store.isSendingTestNotification)
    }

    @ViewBuilder
    private var notificationTestAccessory: some View {
        if store.isSendingTestNotification {
            ProgressView()
                .controlSize(.small)
        } else if store.notificationTestResult?.isSuccess == true {
            Label("Sent", systemImage: "checkmark.circle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)
        } else {
            Text("Send")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.blue)
        }
    }

    @ViewBuilder
    private func permissionGuidance(embedded: Bool) -> some View {
        switch store.notificationPermissionStatus {
        case .denied:
            permissionCard(
                title: "Notifications are turned off",
                message: "Allow LoopBar notifications in System Settings to receive agent updates.",
                symbol: "bell.slash.fill",
                color: .orange,
                embedded: embedded,
                showsSettingsButton: true
            )
        case .alertsDisabled:
            permissionCard(
                title: "Notification banners are off",
                message: "Choose Banners for LoopBar in System Settings so alerts appear on screen.",
                symbol: "rectangle.on.rectangle.slash.fill",
                color: .orange,
                embedded: embedded,
                showsSettingsButton: true
            )
        case .notRequested:
            permissionCard(
                title: "Notification permission required",
                message: "Choose Test notification and allow alerts when macOS asks.",
                symbol: "bell.badge.fill",
                color: .blue,
                embedded: embedded,
                showsSettingsButton: false
            )
        case let .unavailable(message):
            permissionCard(
                title: "Notifications unavailable",
                message: message,
                symbol: "exclamationmark.triangle.fill",
                color: .orange,
                embedded: embedded,
                showsSettingsButton: false
            )
        case .checking, .allowed:
            EmptyView()
        }

        if case let .failed(message) = store.notificationTestResult {
            permissionCard(
                title: "Notification could not be sent",
                message: message,
                symbol: "exclamationmark.triangle.fill",
                color: .red,
                embedded: embedded,
                showsSettingsButton: false
            )
        }
    }

    private func permissionCard(
        title: String,
        message: String,
        symbol: String,
        color: Color,
        embedded: Bool,
        showsSettingsButton: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(embedded ? .white.opacity(0.56) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if showsSettingsButton {
                    Button("Open System Settings") {
                        store.openNotificationSettings()
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.link)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(color.opacity(embedded ? 0.09 : 0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        }
    }

    private func preferenceToggle(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.48))
                }
            }

            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sourceToggle(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.48))
            }

            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
