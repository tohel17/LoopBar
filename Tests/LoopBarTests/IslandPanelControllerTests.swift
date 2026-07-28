import CoreGraphics
import XCTest
@testable import LoopBar

final class IslandPanelControllerTests: XCTestCase {
    private let panelFrame = CGRect(x: 100, y: 500, width: 520, height: 300)

    @MainActor
    func testExpandedIslandCollapsesForClickOutsidePanel() {
        XCTAssertTrue(
            IslandPanelController.shouldCollapseOnOutsideClick(
                isExpanded: true,
                panelFrame: panelFrame,
                clickLocation: CGPoint(x: 50, y: 450)
            )
        )
    }

    @MainActor
    func testExpandedIslandStaysOpenForClickInsidePanel() {
        XCTAssertFalse(
            IslandPanelController.shouldCollapseOnOutsideClick(
                isExpanded: true,
                panelFrame: panelFrame,
                clickLocation: CGPoint(x: 360, y: 650)
            )
        )
    }

    @MainActor
    func testCompactIslandIgnoresOutsideClicks() {
        XCTAssertFalse(
            IslandPanelController.shouldCollapseOnOutsideClick(
                isExpanded: false,
                panelFrame: panelFrame,
                clickLocation: CGPoint(x: 50, y: 450)
            )
        )
    }
}
