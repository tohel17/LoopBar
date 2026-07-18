import CoreGraphics

enum IslandMetrics {
    static let compactWidth: CGFloat = 400
    static let expandedWidth: CGFloat = 380
    static let compactShadowPadding: CGFloat = 10
    static let expandedShadowPadding: CGFloat = 18

    static func listHeight(agentCount: Int) -> CGFloat {
        guard agentCount > 0 else { return 56 }
        return min(CGFloat(agentCount) * 72 + 20, 250)
    }

    static func contentHeight(expanded: Bool, agentCount: Int, hasError: Bool) -> CGFloat {
        if !expanded {
            return 44 + compactShadowPadding
        }

        let header: CGFloat = 58
        let footer: CGFloat = 46
        let dividers: CGFloat = 2
        let errorBlock: CGFloat = hasError ? 28 : 0
        return header + listHeight(agentCount: agentCount) + errorBlock + footer + dividers + expandedShadowPadding
    }

    static func size(expanded: Bool, agentCount: Int, hasError: Bool) -> CGSize {
        CGSize(
            width: expanded ? expandedWidth : compactWidth,
            height: contentHeight(expanded: expanded, agentCount: agentCount, hasError: hasError)
        )
    }
}
