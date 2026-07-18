import Foundation

/// Visual / interaction mode of the notch island.
///
/// `.loading` and `.notification` use the same expanded chrome and sizing as
/// `.expanded`; only `.compact` collapses the panel.
enum IslandState: Equatable, Sendable {
    case compact
    case expanded
    case loading
    case notification

    /// Whether the island should render expanded chrome and metrics.
    var isExpandedChrome: Bool {
        switch self {
        case .compact:
            return false
        case .expanded, .loading, .notification:
            return true
        }
    }
}
