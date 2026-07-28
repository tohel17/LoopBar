import XCTest
@testable import LoopBar

final class EmptyAgentsCopyTests: XCTestCase {
    func testConnectingBeforeFirstRefresh() {
        XCTAssertEqual(EmptyAgentsCopy.title(lastUpdated: nil, errorMessage: nil), "Connecting…")
        XCTAssertEqual(
            EmptyAgentsCopy.detail(
                lastUpdated: nil,
                errorMessage: nil,
                cursorEnabled: true,
                codexEnabled: true,
                claudeEnabled: true
            ),
            "Checking enabled sources"
        )
    }

    func testEmptyAfterRefreshExplainsSources() {
        let now = Date()
        XCTAssertEqual(EmptyAgentsCopy.title(lastUpdated: now, errorMessage: nil), "No recent agents")
        XCTAssertEqual(
            EmptyAgentsCopy.detail(
                lastUpdated: now,
                errorMessage: nil,
                cursorEnabled: true,
                codexEnabled: false,
                claudeEnabled: false
            ),
            "No recent Cursor activity on this Mac. Open a chat in one of those apps, then refresh."
        )
    }

    func testErrorSurfacesInDetail() {
        let now = Date()
        XCTAssertEqual(
            EmptyAgentsCopy.title(lastUpdated: now, errorMessage: "Cursor: missing db"),
            "Nothing to show yet"
        )
        XCTAssertEqual(
            EmptyAgentsCopy.detail(
                lastUpdated: now,
                errorMessage: "Cursor: missing db",
                cursorEnabled: true,
                codexEnabled: true,
                claudeEnabled: true
            ),
            "Cursor: missing db"
        )
    }
}
