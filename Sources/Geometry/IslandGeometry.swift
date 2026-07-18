import AppKit

/// Pure screen / frame calculations for the floating island panel.
///
/// Keeps all notch and desktop-edge math out of `IslandPanelController`.
enum IslandGeometry {
    /// Prefer the built-in notched display; fall back to the main screen.
    static func targetScreen() -> NSScreen? {
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// Frame that keeps the island centered under the notch / menu bar,
    /// fully inside the visible desktop area.
    static func panelFrame(for contentSize: CGSize, on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let hasNotch = screen.safeAreaInsets.top > 0
        let size = NSSize(width: contentSize.width, height: contentSize.height)

        var x = screenFrame.midX - (size.width / 2)
        x = min(max(x, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)

        // Distance from the very top of the display
        let topInset: CGFloat = hasNotch ? 0 : 12

        // Position relative to the full screen instead of visibleFrame
        let y = screenFrame.maxY - size.height - topInset

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
