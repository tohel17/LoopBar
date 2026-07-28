import Foundation

/// Runs `sqlite3 -json` without deadlocking on large result sets.
///
/// `Process.waitUntilExit()` before draining stdout will hang once the OS pipe
/// buffer fills (~64KB). Cursor bubble dumps for a busy composer routinely
/// exceed that, which leaves LoopBar stuck on "Connecting…".
enum SQLiteJSONQuery {
    struct Result: Sendable {
        var status: Int32
        var stdout: Data
        var stderr: String
    }

    static func run(
        database: URL,
        query: String,
        busyTimeoutMS: Int = 1000
    ) throws -> Result {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-readonly",
            "-cmd", ".timeout \(busyTimeoutMS)",
            "-json",
            database.path,
            query
        ]
        process.standardOutput = output
        process.standardError = error

        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutBox.data = output.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrBox.data = error.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        try process.run()
        process.waitUntilExit()
        group.wait()

        let stderrText = String(data: stderrBox.data, encoding: .utf8) ?? ""
        return Result(
            status: process.terminationStatus,
            stdout: stdoutBox.data,
            stderr: stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// sqlite3 `-json` prints nothing (not `[]`) when a query returns zero rows.
    static func decodeRows<T: Decodable>(_ type: [T].Type, from data: Data) throws -> [T] {
        let trimmed = data.trimmingASCIIWhitespace
        guard !trimmed.isEmpty else { return [] }
        return try JSONDecoder().decode(type, from: trimmed)
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

private extension Data {
    var trimmingASCIIWhitespace: Data {
        let whitespace = Set<UInt8>([0x09, 0x0A, 0x0D, 0x20])
        var start = startIndex
        var end = endIndex
        while start < end, whitespace.contains(self[start]) { start += 1 }
        while end > start, whitespace.contains(self[end - 1]) { end -= 1 }
        return self[start..<end]
    }
}
