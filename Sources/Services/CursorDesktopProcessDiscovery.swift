import Foundation

/// Uses the process table only as an application-level guard. Cursor Desktop
/// shares Electron processes across composers, so this must never be used to
/// attribute liveness to one specific composer.
struct CursorDesktopProcessDiscovery {
    func isRunning() -> Bool? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Ao", "command="]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        return text.split(whereSeparator: \.isNewline).contains { line in
            let command = line.lowercased()
            return command.contains("cursor")
                && (
                    command.contains(".app/contents/macos/cursor")
                        || command.contains(".app/contents/frameworks/cursor helper")
                )
        }
    }
}
