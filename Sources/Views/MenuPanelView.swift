import AppKit
import SwiftUI

/// Composes the island chrome: compact header, optional expanded body, and footer.
struct MenuPanelView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var viewModel: IslandViewModel

    private var expanded: Bool { viewModel.isExpandedChrome }

    var body: some View {
        VStack(spacing: 0) {
            CompactIslandView(store: store, viewModel: viewModel)

            if expanded {
                islandDivider
                ExpandedIslandView(store: store, viewModel: viewModel)
                islandDivider
                islandFooter
            }
        }
        .frame(width: expanded ? IslandMetrics.expandedWidth : IslandMetrics.compactWidth)
        .background {
            IslandShape(expanded: expanded)
                .fill(Color.black)
        }
        .clipShape(IslandShape(expanded: expanded))
        .preferredColorScheme(.dark)
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
                viewModel.selectContent(.settings)
            }
            IslandIconButton(symbol: "power") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 12)
    }

    private var islandDivider: some View {
        Rectangle()
            .fill(Color.black)
            .frame(height: 1)
            .padding(.horizontal, 28)
    }
}

private struct IslandShape: Shape {
    let expanded: Bool

    func path(in rect: CGRect) -> Path {
        let bodyInset = expanded ? 15.0 : 13.0
        let shoulderRadius = expanded ? 16.0 : 14.0
        let bottomRadius = min(expanded ? 24.0 : 22.0, rect.height / 2)

        let bodyMinX = rect.minX + bodyInset
        let bodyMaxX = rect.maxX - bodyInset
        let topMinX = max(rect.minX, bodyMinX - shoulderRadius)
        let topMaxX = min(rect.maxX, bodyMaxX + shoulderRadius)
        var path = Path()

        path.move(to: CGPoint(x: topMinX, y: rect.minY))
        path.addLine(to: CGPoint(x: topMaxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: bodyMaxX, y: rect.minY + shoulderRadius),
            control: CGPoint(x: bodyMaxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: bodyMaxX, y: rect.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: bodyMaxX - bottomRadius, y: rect.maxY),
            control: CGPoint(x: bodyMaxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: bodyMinX + bottomRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: bodyMinX, y: rect.maxY - bottomRadius),
            control: CGPoint(x: bodyMinX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: bodyMinX, y: rect.minY + shoulderRadius))
        path.addQuadCurve(
            to: CGPoint(x: topMinX, y: rect.minY),
            control: CGPoint(x: bodyMinX, y: rect.minY)
        )
        path.closeSubpath()

        return path
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
                .background(Color.black, in: Circle())
        }
        .buttonStyle(.plain)
        .help(symbol == "arrow.clockwise" ? "Refresh now" : symbol == "gearshape" ? "Settings" : "Quit LoopBar")
    }
}
