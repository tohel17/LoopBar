import Foundation

enum AgentStatus: String, Codable, CaseIterable, Sendable {
    case running, queued, completed, failed, cancelled, unknown

    init(apiValue: String?) {
        switch apiValue?.uppercased().replacingOccurrences(of: "-", with: "_") {
        case "RUNNING", "IN_PROGRESS", "WORKING": self = .running
        case "QUEUED", "PENDING", "CREATING": self = .queued
        case "COMPLETED", "COMPLETE", "SUCCEEDED", "SUCCESS": self = .completed
        case "FAILED", "ERROR": self = .failed
        case "CANCELLED", "CANCELED": self = .cancelled
        default: self = .unknown
        }
    }

    var isTerminal: Bool { [.completed, .failed, .cancelled].contains(self) }
    var label: String { rawValue.capitalized }
    var symbol: String { switch self { case .running: "arrow.triangle.2.circlepath"; case .queued: "clock"; case .completed: "checkmark.circle.fill"; case .failed: "xmark.octagon.fill"; case .cancelled: "slash.circle"; case .unknown: "questionmark.circle" } }
}

enum AgentSource: String, Codable, Sendable {
    case cursor = "Cursor"
    case codex = "Codex"
}

struct CursorAgent: Identifiable, Equatable, Sendable {
    let id: String
    let source: AgentSource
    let title: String
    let status: AgentStatus
    let progress: Double?
    let latestStatus: String
    let updatedAt: Date?
    let url: URL?

    init(
        id: String,
        source: AgentSource = .cursor,
        title: String,
        status: AgentStatus,
        progress: Double?,
        latestStatus: String,
        updatedAt: Date?,
        url: URL?
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.status = status
        self.progress = progress
        self.latestStatus = latestStatus
        self.updatedAt = updatedAt
        self.url = url
    }
}
