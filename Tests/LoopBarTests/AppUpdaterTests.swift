import XCTest
@testable import LoopBar

final class AppUpdaterTests: XCTestCase {
    @MainActor
    func testRecognizesSystemApplicationsFolder() {
        XCTAssertTrue(
            AppUpdater.isInstalledInApplications(
                bundleURL: URL(fileURLWithPath: "/Applications/LoopBar.app")
            )
        )
    }

    @MainActor
    func testRecognizesUserApplicationsFolder() {
        XCTAssertTrue(
            AppUpdater.isInstalledInApplications(
                bundleURL: URL(fileURLWithPath: "/Users/example/Applications/LoopBar.app"),
                homeDirectory: URL(fileURLWithPath: "/Users/example")
            )
        )
    }

    @MainActor
    func testRejectsDownloadsDiskImagesAndSimilarPrefixes() {
        let home = URL(fileURLWithPath: "/Users/example")

        XCTAssertFalse(
            AppUpdater.isInstalledInApplications(
                bundleURL: URL(fileURLWithPath: "/Users/example/Downloads/LoopBar.app"),
                homeDirectory: home
            )
        )
        XCTAssertFalse(
            AppUpdater.isInstalledInApplications(
                bundleURL: URL(fileURLWithPath: "/Volumes/LoopBar/LoopBar.app"),
                homeDirectory: home
            )
        )
        XCTAssertFalse(
            AppUpdater.isInstalledInApplications(
                bundleURL: URL(fileURLWithPath: "/Applications Backup/LoopBar.app"),
                homeDirectory: home
            )
        )
    }
}
