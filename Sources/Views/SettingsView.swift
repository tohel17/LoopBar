import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AgentStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Local Cursor") {
                Text("Monitoring your three most recently updated, unarchived Cursor composers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Refresh") {
                Slider(value: $store.settings.refreshSeconds, in: 5...60, step: 1) {
                    Text("Refresh interval")
                } minimumValueLabel: {
                    Text("5s")
                } maximumValueLabel: {
                    Text("60s")
                }
                Text("Every \(Int(store.settings.refreshSeconds)) seconds")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 420)
        .navigationTitle("LoopBar settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    store.updateSettings()
                    dismiss()
                }
            }
        }
    }
}
