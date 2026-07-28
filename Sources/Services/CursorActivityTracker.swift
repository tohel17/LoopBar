import Foundation

/// Tracks Cursor's cross-refresh state transition for follow-ups. Cursor can
/// leave composerData.status as "aborted" throughout an active follow-up, but
/// advances the composer timestamp when that follow-up is submitted and writes
/// "completed" when it finishes.
final class CursorActivityTracker: @unchecked Sendable {
    private struct Observation {
        let updatedAt: Date
        let rawStatus: String
        let inferredRunning: Bool
        let inferredSince: Date?
    }

    private let lock = NSLock()
    private var observations: [String: Observation] = [:]
    private let maximumInferredRun: TimeInterval = 6 * 60 * 60

    /// - Parameter isRecentlyUpdated: Recent activity from any live signal
    ///   (header, bubble, or transcript) — not header `lastUpdatedAt` alone.
    ///   Cursor often freezes the composer header timestamp mid-run.
    /// - Parameter hasDirectRunningEvidence: Loading bubbles, legacy generation
    ///   flags, or an open transcript turn.
    func isInferredRunning(
        composerID: String,
        updatedAt: Date,
        rawStatus: String?,
        isRecentlyUpdated: Bool,
        hasDirectRunningEvidence: Bool,
        isCursorRunning: Bool?
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let normalized = normalize(rawStatus)
        let previous = observations[composerID]
        let isDefinitivelyTerminal = Self.definitiveTerminalStatuses
            .contains(normalized)
        let isAmbiguous = Self.ambiguousStatuses.contains(normalized)

        var inferredRunning = false
        var inferredSince: Date?

        if isCursorRunning == false || isDefinitivelyTerminal {
            inferredRunning = false
        } else if hasDirectRunningEvidence {
            inferredRunning = true
            inferredSince = previous?.inferredSince ?? now
        } else if previous == nil, isAmbiguous, isRecentlyUpdated {
            // Covers LoopBar launching after the follow-up was submitted but
            // before Cursor writes its eventual completed status.
            inferredRunning = true
            inferredSince = now
        } else if let previous {
            let timestampAdvanced = updatedAt > previous.updatedAt
            let previousCanStartFollowUp =
                Self.ambiguousStatuses.contains(previous.rawStatus)
                || Self.definitiveTerminalStatuses.contains(previous.rawStatus)

            if timestampAdvanced, isAmbiguous, previousCanStartFollowUp {
                inferredRunning = true
                inferredSince = now
            } else if previous.inferredRunning, isAmbiguous {
                // Sustain on fresh activity (bubbles/transcript/header) or
                // direct running evidence. Do not clear solely because the
                // composer header timestamp went stale mid-run.
                if !isRecentlyUpdated, !hasDirectRunningEvidence {
                    inferredRunning = false
                } else {
                    let started = previous.inferredSince ?? now
                    inferredRunning = now.timeIntervalSince(started)
                        < maximumInferredRun
                    inferredSince = started
                }
            }
        }

        observations[composerID] = Observation(
            updatedAt: max(updatedAt, previous?.updatedAt ?? .distantPast),
            rawStatus: normalized,
            inferredRunning: inferredRunning,
            inferredSince: inferredSince
        )
        return inferredRunning
    }

    func retain(composerIDs: Set<String>) {
        lock.lock()
        observations = observations.filter { composerIDs.contains($0.key) }
        lock.unlock()
    }

    private func normalize(_ status: String?) -> String {
        status?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static let ambiguousStatuses: Set<String> = [
        "", "none", "unknown", "aborted"
    ]

    private static let definitiveTerminalStatuses: Set<String> = [
        "completed", "complete", "succeeded", "success",
        "failed", "error", "cancelled", "canceled"
    ]
}
