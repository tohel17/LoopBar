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
        .padding(isEmbedded ? 16 : 16)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.purple)
                    .frame(width: 28, height: 28)
                    .background(.purple.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local agents")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Monitors Cursor composers and Codex tasks")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.52))
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Refresh interval")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(Int(store.settings.refreshSeconds)) sec")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.purple.opacity(0.95))
                }
                Slider(value: $store.settings.refreshSeconds, in: 1...60, step: 1)
                    .tint(.purple)
                HStack {
                    Text("1 second")
                    Spacer()
                    Text("1 minute")
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.42))
            }

            Button(action: finish) {
                Text("Done")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
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
