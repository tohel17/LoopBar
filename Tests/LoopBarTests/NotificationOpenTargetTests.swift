import XCTest
@testable import LoopBar

final class NotificationOpenTargetTests: XCTestCase {
    func testUsesExplicitSourceOverFileScheme() {
        let url = URL(fileURLWithPath: "/Users/me/project")
        let target = NotificationOpenTarget.resolve(
            agentURL: url.absoluteString,
            agentSource: AgentSource.cursor.rawValue
        )
        XCTAssertEqual(target, .open(url: url, source: .cursor))
    }

    func testCodexSchemeWithoutSource() {
        let target = NotificationOpenTarget.resolve(
            agentURL: "codex://threads/abc",
            agentSource: nil
        )
        XCTAssertEqual(target?.source, .codex)
        XCTAssertEqual(target?.url.scheme, "codex")
    }

    func testFileSchemeWithoutSourceDefaultsToCursorNotClaude() {
        // Cursor workspace links are file://. Inferring Claude from file://
        // opened the folder in whatever editor last claimed it (e.g. Antigravity).
        let url = URL(fileURLWithPath: "/Users/me/project")
        let target = NotificationOpenTarget.resolve(
            agentURL: url.absoluteString,
            agentSource: nil
        )
        XCTAssertEqual(target, .open(url: url, source: .cursor))
    }

    func testExplicitClaudeSourceKeptForFileURL() {
        let url = URL(fileURLWithPath: "/Users/me/claude-project")
        let target = NotificationOpenTarget.resolve(
            agentURL: url.absoluteString,
            agentSource: AgentSource.claude.rawValue
        )
        XCTAssertEqual(target, .open(url: url, source: .claude))
    }

    func testMissingURLReturnsNil() {
        XCTAssertNil(NotificationOpenTarget.resolve(agentURL: nil, agentSource: "cursor"))
        XCTAssertNil(NotificationOpenTarget.resolve(agentURL: "not a url", agentSource: nil))
    }
}
