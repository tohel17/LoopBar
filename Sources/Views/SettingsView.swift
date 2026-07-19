import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AgentStore
    /// When embedded in the island, dismiss returns to the agents pane.
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

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
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.purple)
                    .frame(width: 34, height: 34)
                    .background(.purple.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local agents")
                        .font(.system(size: 16, weight: .bold))
                    Text("Monitors Cursor composers and Codex tasks")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Refresh interval")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("\(Int(store.settings.refreshSeconds)) sec")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple.opacity(0.95))
                }
                Slider(value: $store.settings.refreshSeconds, in: 1...60, step: 1)
                    .tint(.purple)
                HStack {
                    Text("1 second")
                    Spacer()
                    Text("1 minute")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.42))
            }

            sourceToggles

            Button(action: finish) {
                Text("Done")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
            Slider(value: $store.settings.refreshSeconds, in: 1...60, step: 1) {
                Text("Refresh interval")
            } minimumValueLabel: {
                Text("1s")
            } maximumValueLabel: {
                Text("60s")
            }
            Text("Every \(Int(store.settings.refreshSeconds)) seconds")
                .foregroundStyle(.secondary)
        }
        Section("Sources") {
            Toggle("Monitor Cursor", isOn: $store.settings.cursorEnabled)
            Toggle("Monitor Codex", isOn: $store.settings.codexEnabled)
            Text("Disabled sources are not polled and do not produce errors or notifications.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
