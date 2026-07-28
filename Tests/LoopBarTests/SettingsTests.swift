import Foundation
import XCTest
@testable import LoopBar

final class SettingsTests: XCTestCase {
    @MainActor
    func testOnboardingIsOnlyCompletedExplicitlyAndPersists() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = Settings(defaults: defaults)
        XCTAssertFalse(settings.hasCompletedOnboarding)

        settings.completeOnboarding()

        XCTAssertTrue(Settings(defaults: defaults).hasCompletedOnboarding)
    }

    @MainActor
    func testToolSelectionsPersistAcrossLaunches() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = Settings(defaults: defaults)
        settings.cursorEnabled = false
        settings.codexEnabled = true
        settings.claudeEnabled = false

        let relaunched = Settings(defaults: defaults)
        XCTAssertFalse(relaunched.cursorEnabled)
        XCTAssertTrue(relaunched.codexEnabled)
        XCTAssertFalse(relaunched.claudeEnabled)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "LoopBarTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
