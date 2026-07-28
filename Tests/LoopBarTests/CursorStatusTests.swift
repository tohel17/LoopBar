import XCTest
@testable import LoopBar

final class CursorStatusTests: XCTestCase {
    func testOpenUserTurnIsRunningWithoutTurnStarted() {
        let jsonl = """
        {"role":"user","message":{"content":[{"type":"text","text":"hello"}]}}
        """

        XCTAssertEqual(
            CursorTranscriptMonitor.turnState(fromJSONL: jsonl),
            .running
        )
    }

    func testTurnEndedSuccessIsCompleted() {
        let jsonl = """
        {"role":"user","message":{"content":[{"type":"text","text":"hello"}]}}
        {"role":"assistant","message":{"content":[{"type":"text","text":"done"}]}}
        {"type":"turn_ended","status":"success"}
        """

        XCTAssertEqual(
            CursorTranscriptMonitor.turnState(fromJSONL: jsonl),
            .completed
        )
    }

    func testTurnEndedErrorIsFailed() {
        let jsonl = """
        {"role":"user","message":{"content":[{"type":"text","text":"hello"}]}}
        {"type":"turn_ended","status":"error"}
        """

        XCTAssertEqual(
            CursorTranscriptMonitor.turnState(fromJSONL: jsonl),
            .failed
        )
    }

    func testFollowUpUserMessageReopensCompletedTurn() {
        let jsonl = """
        {"role":"user","message":{"content":[{"type":"text","text":"one"}]}}
        {"type":"turn_ended","status":"success"}
        {"role":"user","message":{"content":[{"type":"text","text":"two"}]}}
        """

        XCTAssertEqual(
            CursorTranscriptMonitor.turnState(fromJSONL: jsonl),
            .running
        )
    }

    func testAssistantAfterCompletedDoesNotReopenTurn() {
        let jsonl = """
        {"role":"user","message":{"content":[{"type":"text","text":"one"}]}}
        {"type":"turn_ended","status":"success"}
        {"role":"assistant","message":{"content":[{"type":"text","text":"late"}]}}
        """

        XCTAssertEqual(
            CursorTranscriptMonitor.turnState(fromJSONL: jsonl),
            .completed
        )
    }

    func testAbortedWithRecentLoadingBubbleIsRunning() {
        let status = CursorAPI.status(
            composerStatus: "aborted",
            hasLiveGeneration: true,
            hasPendingPlan: false,
            hasUnreadMessages: false,
            hasBlockingPendingActions: false,
            queueItemCount: 0,
            hasCompletionSubtitle: false,
            transcriptState: .none,
            isRecentlyActive: false,
            isCursorRunning: true,
            inferredFollowUpRunning: false
        )

        XCTAssertEqual(status, .running)
    }

    func testCompletedWithoutLiveBubbleStaysCompleted() {
        let status = CursorAPI.status(
            composerStatus: "completed",
            hasLiveGeneration: false,
            hasPendingPlan: false,
            hasUnreadMessages: false,
            hasBlockingPendingActions: false,
            queueItemCount: 0,
            hasCompletionSubtitle: false,
            transcriptState: .completed,
            isRecentlyActive: true,
            isCursorRunning: true,
            inferredFollowUpRunning: false
        )

        XCTAssertEqual(status, .completed)
    }

    func testStaleLoadingBubbleIsIgnoredViaHasLiveGenerationFalse() {
        let now = Date()
        let stale = now.addingTimeInterval(-60)
        XCTAssertFalse(CursorAPI.isRecentLoadingBubble(createdAt: stale, now: now))
        XCTAssertTrue(
            CursorAPI.isRecentLoadingBubble(
                createdAt: now.addingTimeInterval(-5),
                now: now
            )
        )

        let status = CursorAPI.status(
            composerStatus: "aborted",
            hasLiveGeneration: false,
            hasPendingPlan: false,
            hasUnreadMessages: false,
            hasBlockingPendingActions: false,
            queueItemCount: 0,
            hasCompletionSubtitle: false,
            transcriptState: .none,
            isRecentlyActive: false,
            isCursorRunning: true,
            inferredFollowUpRunning: false
        )

        XCTAssertEqual(status, .unknown)
    }

    func testOpenTranscriptTurnIsRunningWhileCursorIsOpen() {
        let status = CursorAPI.status(
            composerStatus: "aborted",
            hasLiveGeneration: false,
            hasPendingPlan: false,
            hasUnreadMessages: false,
            hasBlockingPendingActions: false,
            queueItemCount: 0,
            hasCompletionSubtitle: false,
            transcriptState: .running,
            isRecentlyActive: false,
            isCursorRunning: true,
            inferredFollowUpRunning: false
        )

        XCTAssertEqual(status, .running)
    }

    func testActivityTrackerSustainsOnRecentActivityWithoutHeaderFreshness() {
        let tracker = CursorActivityTracker()
        let started = Date().addingTimeInterval(-30)

        // First observation: ambiguous + recent activity starts inference.
        XCTAssertTrue(
            tracker.isInferredRunning(
                composerID: "c1",
                updatedAt: started,
                rawStatus: "aborted",
                isRecentlyUpdated: true,
                hasDirectRunningEvidence: false,
                isCursorRunning: true
            )
        )

        // Header timestamp unchanged, but bubble/transcript activity is still
        // recent — inference must continue.
        XCTAssertTrue(
            tracker.isInferredRunning(
                composerID: "c1",
                updatedAt: started,
                rawStatus: "aborted",
                isRecentlyUpdated: true,
                hasDirectRunningEvidence: false,
                isCursorRunning: true
            )
        )

        // No recent activity and no direct evidence → clear inference.
        XCTAssertFalse(
            tracker.isInferredRunning(
                composerID: "c1",
                updatedAt: started,
                rawStatus: "aborted",
                isRecentlyUpdated: false,
                hasDirectRunningEvidence: false,
                isCursorRunning: true
            )
        )
    }
}
