import XCTest
import UserNotifications
@testable import LoopBar

final class NotificationLogoTests: XCTestCase {
    func testAttachmentIsCreatedFromReadablePNG() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("loopbar-logo-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temp) }

        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Resources/NotificationLogo.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "Missing \(source.path)")
        try FileManager.default.copyItem(at: source, to: temp)

        let attachment = NotificationLogo.makeAttachment(from: temp)
        XCTAssertNotNil(attachment)
        XCTAssertEqual(attachment?.identifier, NotificationLogo.attachmentIdentifier)
        XCTAssertFalse(attachment?.url.path.isEmpty ?? true)
    }

    func testMissingFileReturnsNil() {
        let missing = URL(fileURLWithPath: "/tmp/loopbar-missing-\(UUID().uuidString).png")
        XCTAssertNil(NotificationLogo.makeAttachment(from: missing))
    }
}
