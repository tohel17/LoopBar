import XCTest
@testable import LoopBar

final class CodexAPIStatusTests: XCTestCase {
    func testHybridExecCallRemainsRunning() {
        let rollout = """
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","status":"completed"}}
        """

        XCTAssertEqual(CodexAPI.status(fromRollout: rollout, isRecentlyUpdated: true), .running)
    }

    func testHybridExecOutputRemainsRunning() {
        let rollout = """
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","status":"completed"}}
        {"type":"response_item","payload":{"type":"custom_tool_call_output"}}
        """

        XCTAssertEqual(CodexAPI.status(fromRollout: rollout, isRecentlyUpdated: true), .running)
    }

    func testCompletedLifecycleWinsOverRecentDatabaseUpdate() {
        let rollout = """
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"event_msg","payload":{"type":"task_complete"}}
        """

        XCTAssertEqual(CodexAPI.status(fromRollout: rollout, isRecentlyUpdated: true), .completed)
    }

    func testExplicitApprovalStillNeedsAttention() {
        let rollout = """
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"event_msg","payload":{"type":"permissions_request_approval"}}
        """

        XCTAssertEqual(CodexAPI.status(fromRollout: rollout, isRecentlyUpdated: true), .waitingForApproval)
    }

    func testPendingEscalatedCommandNeedsApproval() {
        let rollout = """
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"npm install\\",\\"sandbox_permissions\\":\\"require_escalated\\"}","call_id":"call-1"}}
        {"type":"event_msg","payload":{"type":"token_count"}}
        """

        XCTAssertEqual(
            CodexAPI.status(
                fromRollout: rollout,
                isRecentlyUpdated: true,
                approvalMode: "on-request"
            ),
            .waitingForApproval
        )
    }

    func testApprovalOutputResumesRunning() {
        let rollout = """
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"npm install\\",\\"sandbox_permissions\\":\\"require_escalated\\"}","call_id":"call-1"}}
        {"type":"response_item","payload":{"type":"function_call_output","call_id":"call-1","output":"rejected by user"}}
        """

        XCTAssertEqual(
            CodexAPI.status(
                fromRollout: rollout,
                isRecentlyUpdated: true,
                approvalMode: "on-request"
            ),
            .running
        )
    }

    func testPendingCodeModeExecNeedsApproval() {
        let rollout = """
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"const result = await tools.exec_command({cmd: \\"npm install\\", sandbox_permissions: \\"require_escalated\\"});","call_id":"call-code-mode","status":"completed"}}
        """

        XCTAssertEqual(
            CodexAPI.status(
                fromRollout: rollout,
                isRecentlyUpdated: true,
                approvalMode: "on-request"
            ),
            .waitingForApproval
        )
    }

    func testCodeModeExecOutputResumesRunning() {
        let rollout = """
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"const result = await tools.exec_command({cmd: \\"npm install\\", sandbox_permissions: \\"require_escalated\\"});","call_id":"call-code-mode","status":"completed"}}
        {"type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"call-code-mode","output":"Script completed"}}
        """

        XCTAssertEqual(
            CodexAPI.status(
                fromRollout: rollout,
                isRecentlyUpdated: true,
                approvalMode: "on-request"
            ),
            .running
        )
    }

    func testNeverApprovalModeDoesNotCreateWaitState() {
        let rollout = """
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"npm install\\",\\"sandbox_permissions\\":\\"require_escalated\\"}","call_id":"call-1"}}
        """

        XCTAssertEqual(
            CodexAPI.status(
                fromRollout: rollout,
                isRecentlyUpdated: true,
                approvalMode: "never"
            ),
            .running
        )
    }

    func testStatusTextInsideMessageDoesNotCreateWaitState() {
        let rollout = """
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"event_msg","payload":{"type":"agent_message","message":"Example: \\"type\\":\\"permissions_request_approval\\""}}
        """

        XCTAssertEqual(
            CodexAPI.status(fromRollout: rollout, isRecentlyUpdated: true),
            .running
        )
    }

    func testPendingUserInputCallWaitsForResponse() {
        let rollout = """
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"response_item","payload":{"type":"function_call","name":"request_user_input","arguments":"{}","call_id":"call-input"}}
        """

        XCTAssertEqual(
            CodexAPI.status(fromRollout: rollout, isRecentlyUpdated: true),
            .waitingForInput
        )
    }

    func testSemanticRunningSurvivesStaleDatabaseRecencyForDesktopTask() {
        XCTAssertEqual(
            CodexAPI.reconciledStatus(
                semanticStatus: .running,
                isProcessLive: false,
                canDetermineProcessAbsence: false,
                isRecentlyActive: false
            ),
            .running
        )
    }

    func testTerminalCLIAbsenceOverridesUnfinishedLifecycle() {
        XCTAssertEqual(
            CodexAPI.reconciledStatus(
                semanticStatus: .running,
                isProcessLive: false,
                canDetermineProcessAbsence: true,
                isRecentlyActive: false
            ),
            .unknown
        )
    }

    func testLifecycleBeforeBoundedTailRemainsRunning() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        let start = """
        {"type":"event_msg","payload":{"type":"task_started"}}

        """
        var data = Data(start.utf8)
        data.append(Data(repeating: Character("x").asciiValue!, count: 1_200_000))
        data.append(Data("\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\"}}\n".utf8))
        try data.write(to: url)

        XCTAssertEqual(
            CodexAPI.status(
                fromRolloutAt: url.path,
                approvalMode: "on-request"
            ),
            .running
        )
    }
}
