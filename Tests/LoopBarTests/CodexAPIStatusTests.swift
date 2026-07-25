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
}
