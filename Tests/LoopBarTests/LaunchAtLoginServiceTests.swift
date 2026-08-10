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

    @MainActor
    func testPackagedAppCanRetryWhenServiceHasNotBeenFound() {
        XCTAssertTrue(
            LaunchAtLoginService.isAvailable(
                isPackagedApp: true,
                isRunningFromTransientLocation: false
            )
        )
    }

    @MainActor
    func testRawExecutableAndTransientAppAreUnavailable() {
        XCTAssertFalse(
            LaunchAtLoginService.isAvailable(
                isPackagedApp: false,
                isRunningFromTransientLocation: false
            )
        )
        XCTAssertFalse(
            LaunchAtLoginService.isAvailable(
                isPackagedApp: true,
                isRunningFromTransientLocation: true
            )
        )
    }

    @MainActor
    func testDiskImageAndTranslocatedPathsAreTransient() {
        XCTAssertTrue(LaunchAtLoginService.isTransientPath("/Volumes/LoopBar/LoopBar.app"))
        XCTAssertTrue(
            LaunchAtLoginService.isTransientPath(
                "/private/var/folders/example/AppTranslocation/LoopBar.app"
            )
        )
        XCTAssertFalse(LaunchAtLoginService.isTransientPath("/Applications/LoopBar.app"))
    }
}
