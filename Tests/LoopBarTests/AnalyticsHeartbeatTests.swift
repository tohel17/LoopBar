import XCTest
@testable import LoopBar

final class AnalyticsHeartbeatTests: XCTestCase {
    func testHeartbeatRunsEveryTwentyFourHours() {
        XCTAssertEqual(
            AnalyticsService.heartbeatInterval,
            .seconds(86_400)
        )
    }
}
