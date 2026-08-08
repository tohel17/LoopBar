import ServiceManagement
import XCTest
@testable import LoopBar

final class LaunchAtLoginServiceTests: XCTestCase {
    @MainActor
    func testEnabledAndApprovalStatusesRenderAsEnabled() {
        XCTAssertTrue(LaunchAtLoginService.isEnabled(status: .enabled))
        XCTAssertTrue(LaunchAtLoginService.isEnabled(status: .requiresApproval))
    }

    @MainActor
    func testUnregisteredAndMissingStatusesRenderAsDisabled() {
        XCTAssertFalse(LaunchAtLoginService.isEnabled(status: .notRegistered))
        XCTAssertFalse(LaunchAtLoginService.isEnabled(status: .notFound))
    }
}
