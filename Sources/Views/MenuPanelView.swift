import SwiftUI
import AppKit

struct MenuPanelView: View {
    @ObservedObject var store: AgentStore
    @Binding var expanded: Bool
    @State private var showSettings = false

    private var runningCount: Int { store.agents.filter { $0.status == .running }.count }

    var body: some View {
        VStack(spacing: 0) {
            islandHeader

            if expanded {
                islandDivider
                agentSection
                if let error = store.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.9))
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)
                }
                islandDivider
                islandFooter
            }
        }
        .frame(width: expanded ? IslandMetrics.expandedWidth : IslandMetrics.compactWidth)
        .background(islandBackground)
        .overlay {
            IslandShape(expanded: expanded)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
        }
        .shadow(color: .black, radius: expanded ? 28 : 16, y: expanded ? 14 : 8)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store)
        }
    }

    private var islandHeader: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                StatusOrb(isActive: runningCount > 0)

                VStack(alignment: .leading, spacing: 1) {
                    Text(headerTitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(headerSubtitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: expanded ? "chevron.compact.up" : "chevron.compact.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, expanded ? 18 : 16)
            .padding(.vertical, expanded ? 14 : 11)
        }
        .buttonStyle(.plain)
    }

    private var agentSection: some View {
        Group {
            if store.agents.isEmpty {
                Text("No recent composers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(store.agents) { agent in
                            AgentRow(agent: agent)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .frame(height: IslandMetrics.listHeight(agentCount: store.agents.count))
            }
        }
    }

    private var islandFooter: some View {
        HStack(spacing: 12) {
            Text(store.lastUpdated.map { "Updated \($0, style: .relative)" } ?? "Connecting…")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))

            Spacer()

            IslandIconButton(symbol: "arrow.clockwise") {
                Task { await store.refresh() }
            }
            IslandIconButton(symbol: "gearshape") {
                showSettings = true
            }
            IslandIconButton(symbol: "power") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var islandBackground: some View {
        ZStack {
            Color.black
            if runningCount > 0 {
                RadialGradient(
                    colors: [.purple.opacity(0.22), .clear],
                    center: .topLeading,
                    startRadius: 8,
                    endRadius: 180
                )
            }
        }
    }

    private var islandDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private var headerTitle: String {
        if runningCount > 0 {
            return "\(runningCount) active"
        }
        return "LoopBar"
    }

    private var headerSubtitle: String {
        if runningCount > 0 {
            return "\(store.agents.count) composer\(store.agents.count == 1 ? "" : "s") nearby"
        }
        if store.agents.isEmpty {
            return "Waiting for Cursor"
        }
        return "\(store.agents.count) recent composer\(store.agents.count == 1 ? "" : "s")"
    }
}

private struct IslandShape: Shape {
    let expanded: Bool

    func path(in rect: CGRect) -> Path {
        let radius = expanded ? 28.0 : rect.height / 2
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
    }
}

private struct StatusOrb: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? Color.purple.opacity(0.25) : Color.white.opacity(0.08))
                .frame(width: 22, height: 22)

            Circle()
                .fill(isActive ? Color.purple : Color.green.opacity(0.85))
                .frame(width: 8, height: 8)

            if isActive {
                Circle()
                    .stroke(Color.purple.opacity(0.55), lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                    .scaleEffect(isActive ? 1.15 : 1)
                    .opacity(isActive ? 0.8 : 0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isActive)
            }
        }
        .frame(width: 22, height: 22)
    }
}

private struct IslandIconButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct AgentRow: View {
    let agent: CursorAgent

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: agent.status.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(agent.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(agent.status.label)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(color.opacity(0.9))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.14), in: Capsule())
                }
                Text(agent.latestStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { openInCursor(agent) }
    }

    private var color: Color {
        switch agent.status {
        case .running: .purple
        case .queued: .yellow
        case .completed: .green
        case .failed: .red
        case .cancelled, .unknown: .gray
        }
    }

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
