import SwiftUI
import AppKit

struct MenuPanelView: View {
    @ObservedObject var store: AgentStore
    @Environment(\.openWindow) private var openWindow
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: { CompactNotchHeader(agents: store.agents, expanded: expanded) }
                .buttonStyle(.plain)
            if expanded {
                Divider().overlay(.white.opacity(0.12))
                AgentListView(agents: store.agents)
                if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, 16).padding(.bottom, 8) }
                Divider().overlay(.white.opacity(0.12))
                HStack {
                    Text(store.lastUpdated.map { "Updated \($0, style: .relative)" } ?? "Connecting…").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
                    Button { openWindow(id: "settings") } label: { Image(systemName: "gearshape") }.buttonStyle(.borderless)
                    Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.buttonStyle(.borderless)
                }.padding(12)
            }
        }
        .frame(width: expanded ? 390 : 250)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 22 : 16, style: .continuous))
        .preferredColorScheme(.dark)
    }
}

private struct CompactNotchHeader: View {
    let agents: [CursorAgent]; let expanded: Bool
    var body: some View {
        let running = agents.filter { $0.status == .running }.count
        HStack(spacing: 10) {
            if #available(macOS 15.0, *) {
                Image(systemName: running > 0 ? "cursorarrow.rays" : "checkmark.circle").symbolEffect(.rotate, options: .repeating, isActive: running > 0).foregroundStyle(running > 0 ? .purple : .green)
            } else {
                // Fallback on earlier versions
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(running > 0 ? "\(running) agent\(running == 1 ? "" : "s") running" : "LoopBar").font(.headline)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(); Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 16).padding(.vertical, 13)
    }

    private var summary: String {
        let running = agents.filter { $0.status == .running }.count
        let queued = agents.filter { $0.status == .queued }.count
        if running > 0 { return "\(agents.count) local conversation\(agents.count == 1 ? "" : "s")" }
        if queued > 0 { return "\(queued) queued" }
        return agents.isEmpty ? "No recent agents" : "\(agents.count) local conversation\(agents.count == 1 ? "" : "s")"
    }
}

private struct AgentListView: View {
    let agents: [CursorAgent]
    var body: some View {
        ScrollView { LazyVStack(spacing: 2) { ForEach(agents) { agent in AgentRow(agent: agent) } } }
            .frame(height: min(CGFloat(agents.count) * 78 + 16, 325))
            .padding(8)
    }
}

private struct AgentRow: View {
    let agent: CursorAgent
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: agent.status.symbol).foregroundStyle(color).frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(agent.title).lineLimit(1).fontWeight(.medium); Spacer(); Text(agent.status.label).font(.caption).foregroundStyle(.secondary) }
                Text(agent.latestStatus).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                if let progress = agent.progress { ProgressView(value: progress).tint(color).accessibilityLabel("Progress \(Int(progress * 100)) percent") }
            }
        }.padding(10).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous)).contentShape(Rectangle()).onTapGesture { openInCursor(agent) }
    }
    private var color: Color { switch agent.status { case .running: .purple; case .queued: .yellow; case .completed: .green; case .failed: .red; case .cancelled, .unknown: .gray } }

    private func openInCursor(_ agent: CursorAgent) {
        guard let url = agent.url else { return }
        let cursorApp = URL(fileURLWithPath: "/Applications/Cursor.app")
        if FileManager.default.fileExists(atPath: cursorApp.path) {
            NSWorkspace.shared.open([url], withApplicationAt: cursorApp, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
