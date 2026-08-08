import XCTest
@testable import LoopBar

final class ClaudeAPIStatusTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-07-28T12:00:10Z")!

    func testHeadlessProcessRowsAreKeptForLiveRegistryMatching() {
        let output = """
        93779 93778 ?? /Applications/Claude.app/Contents/MacOS/claude --resume=session-1
        """

        let rows = ClaudeAPI.processRows(from: output)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].pid, 93779)
        XCTAssertEqual(rows[0].tty, "??")
    }

    func testDesktopExecutablePathWithSpacesIsRecognized() {
        let command = "/Users/me/Library/Application Support/Claude/claude-code/2.1.219/claude.app"
            + "/Contents/MacOS/claude --output-format stream-json --permission-mode acceptEdits"

        XCTAssertTrue(ClaudeAPI.isClaudeCommand(command))
    }

    func testTerminalExecutablePathsAreRecognized() {
        XCTAssertTrue(ClaudeAPI.isClaudeCommand("claude"))
        XCTAssertTrue(ClaudeAPI.isClaudeCommand("claude --resume=session-1"))
        XCTAssertTrue(ClaudeAPI.isClaudeCommand("/opt/homebrew/bin/claude fix the failing test"))
    }

    func testNonClaudeCommandsAreRejected() {
        // A launcher whose own path is not Claude Code, even though it passes
        // the real executable along as its first argument.
        XCTAssertFalse(
            ClaudeAPI.isClaudeCommand(
                "/Applications/Claude.app/Contents/Helpers/disclaimer /Users/me/Library/Application"
                    + " Support/Claude/claude-code/2.1.219/claude.app/Contents/MacOS/claude --verbose"
            )
        )
        XCTAssertFalse(ClaudeAPI.isClaudeCommand("tail -f /var/log/claude"))
        XCTAssertFalse(ClaudeAPI.isClaudeCommand("tail /var/log/claude"))
        XCTAssertFalse(ClaudeAPI.isClaudeCommand(""))
    }

    func testClaudeProjectEncodingNormalizesPathPunctuation() {
        XCTAssertEqual(
            ClaudeAPI.encodedProjectPath("/Users/me/My_Project/example.app"),
            "-Users-me-My-Project-example-app"
        )
    }

    func testUnresolvedBashWithoutChildWaitsForApproval() {
        let metadata = ClaudeAPI.transcriptMetadata(from: transcript(tool: "Bash"))

        XCTAssertEqual(
            ClaudeAPI.liveStatus(metadata: metadata, process: process(hasChild: false), now: now),
            .waitingForApproval
        )
    }

    func testUnresolvedBashWithExecutingChildRemainsRunning() {
        let metadata = ClaudeAPI.transcriptMetadata(from: transcript(tool: "Bash"))

        XCTAssertEqual(
            ClaudeAPI.liveStatus(metadata: metadata, process: process(hasChild: true), now: now),
            .running
        )
    }

    func testBashResultClearsApprovalWait() {
        let value = transcript(tool: "Bash") + """

        {"type":"user","timestamp":"2026-07-28T12:00:05Z","message":{"content":[{"type":"tool_result","tool_use_id":"tool-1","content":"done"}]}}
        """
        let metadata = ClaudeAPI.transcriptMetadata(from: value)

        XCTAssertEqual(
            ClaudeAPI.liveStatus(metadata: metadata, process: process(hasChild: false), now: now),
            .running
        )
    }

    func testAskUserQuestionWaitsForInput() {
        let metadata = ClaudeAPI.transcriptMetadata(from: transcript(tool: "AskUserQuestion"))

        XCTAssertEqual(
            ClaudeAPI.liveStatus(metadata: metadata, process: process(hasChild: false), now: now),
            .waitingForInput
        )
    }

    func testAcceptEditsDoesNotTreatEditAsApprovalWait() {
        let metadata = ClaudeAPI.transcriptMetadata(from: transcript(tool: "Edit"))

        XCTAssertEqual(
            ClaudeAPI.liveStatus(
                metadata: metadata,
                process: process(hasChild: false, permissionMode: "acceptEdits"),
                now: now
            ),
            .running
        )
    }

    func testSettledAssistantEndingCompletesInsteadOfRunningForever() {
        let value = """
        {"type":"user","timestamp":"2026-07-28T12:00:00Z","message":{"content":"Please continue"}}
        {"type":"assistant","timestamp":"2026-07-28T12:00:01Z","message":{"model":"claude-opus-5","content":[{"type":"text","text":"All done."}]}}
        """
        let metadata = ClaudeAPI.transcriptMetadata(from: value)

        XCTAssertEqual(metadata.lastRole, "assistant")
        XCTAssertEqual(
            ClaudeAPI.liveStatus(metadata: metadata, process: process(hasChild: false), now: now),
            .completed
        )
    }

    func testFreshAssistantEndingStaysRunningUntilItSettles() {
        let value = """
        {"type":"user","timestamp":"2026-07-28T12:00:00Z","message":{"content":"Please continue"}}
        {"type":"assistant","timestamp":"2026-07-28T12:00:09Z","message":{"model":"claude-opus-5","content":[{"type":"text","text":"Working on it"}]}}
        """
        let metadata = ClaudeAPI.transcriptMetadata(from: value)

        XCTAssertEqual(
            ClaudeAPI.liveStatus(metadata: metadata, process: process(hasChild: false), now: now),
            .running
        )
    }

    func testTrailingUserEntryStaysRunningWhileModelReplies() {
        let value = """
        {"type":"assistant","timestamp":"2026-07-28T11:59:00Z","message":{"model":"claude-opus-5","content":[{"type":"text","text":"Done"}]}}
        {"type":"user","timestamp":"2026-07-28T11:59:30Z","message":{"content":"Now do the next thing"}}
        """
        let metadata = ClaudeAPI.transcriptMetadata(from: value)

        XCTAssertEqual(metadata.lastRole, "user")
        XCTAssertEqual(
            ClaudeAPI.liveStatus(metadata: metadata, process: process(hasChild: false), now: now),
            .running
        )
    }

    func testPendingToolKeepsSessionRunningEvenWhenQuiet() {
        // A settled assistant entry that still owns an unresolved non-approval
        // tool is mid-turn, not finished.
        let metadata = ClaudeAPI.transcriptMetadata(from: transcript(tool: "Read"))

        XCTAssertEqual(
            ClaudeAPI.liveStatus(metadata: metadata, process: process(hasChild: false), now: now),
            .running
        )
    }

    private func transcript(tool: String) -> String {
        """
        {"type":"user","timestamp":"2026-07-28T12:00:00Z","message":{"content":"Please continue"}}
        {"type":"assistant","timestamp":"2026-07-28T12:00:01Z","message":{"model":"claude-opus-5","content":[{"type":"tool_use","id":"tool-1","name":"\(tool)","input":{}}]}}
        """
    }

    private func process(
        hasChild: Bool,
        permissionMode: String = "default"
    ) -> ClaudeProcess {
        ClaudeProcess(
            pid: 93779,
            identity: "pid:93779",
            tty: "??",
            cwd: URL(fileURLWithPath: "/tmp/project"),
            transcriptPath: "/tmp/project/session.jsonl",
            permissionMode: permissionMode,
            hasRunningDescendant: hasChild
        )
    }
}
