import CoreGraphics

/// Sizing constants and helpers for the notch island panel and SwiftUI content.
enum IslandMetrics {
    /// Compact island hugs its header content instead of stretching into a wide pill.
    static let compactWidth: CGFloat = 370
    static let expandedWidth: CGFloat = 520
    static let compactShadowPadding: CGFloat = 0
    static let expandedShadowPadding: CGFloat = 0
    static let settingsBodyHeight: CGFloat = 390

    static func listHeight(agentCount: Int) -> CGFloat {
        guard agentCount > 0 else { return 56 }
        return min(CGFloat(agentCount) * 78 + 20, 258)
    }

    static func bodyHeight(content: IslandContent, agentCount: Int, hasError: Bool) -> CGFloat {
        switch content {
        case .agents:
            let errorBlock: CGFloat = hasError ? 28 : 0
            return listHeight(agentCount: agentCount) + errorBlock
        case .settings:
            return settingsBodyHeight
        case .logs:
            return 104
        }
    }

    static func contentHeight(
        expanded: Bool,
        content: IslandContent = .agents,
        agentCount: Int,
        hasError: Bool
    ) -> CGFloat {
        if !expanded {
            return 50 + compactShadowPadding
        }

        let header: CGFloat = 62
        let footer: CGFloat = 48
        let dividers: CGFloat = 2
        return header
            + bodyHeight(content: content, agentCount: agentCount, hasError: hasError)
            + footer
            + dividers
            + expandedShadowPadding
    }

    static func size(
        expanded: Bool,
        content: IslandContent = .agents,
        agentCount: Int,
        hasError: Bool
    ) -> CGSize {
        CGSize(
            width: expanded ? expandedWidth : compactWidth,
            height: contentHeight(
                expanded: expanded,
                content: content,
                agentCount: agentCount,
                hasError: hasError
            )
        )
    }

    static func shadowPadding(expanded: Bool) -> CGFloat {
        expanded ? expandedShadowPadding : compactShadowPadding
    }
}
