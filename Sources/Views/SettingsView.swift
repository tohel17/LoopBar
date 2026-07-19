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
                    Text("Monitors Cursor composers and Codex tasks")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.52))
                }
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

    @ViewBuilder
    private var settingsContent: some View {
        Section("Local agents") {
            Text("Monitoring your three most recently updated Cursor composers and Codex tasks.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            }
            if !store.settings.notificationsEnabled {
                Text("Notification options are hidden while notifications are disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
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
            Text("Disabled sources are not polled or shown in LoopBar.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.48))
        }
        .toggleStyle(.switch)
        .onChange(of: store.settings.cursorEnabled) { _, _ in store.updateSettings() }
        .onChange(of: store.settings.codexEnabled) { _, _ in store.updateSettings() }
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
            } else {
                Text("Notification options are hidden while disabled.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
        .toggleStyle(.switch)
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
