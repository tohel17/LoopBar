import Foundation

enum AppVersion {
    static let current: String = {
        if let bundledVersion = normalized(
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        ) {
            return bundledVersion
        }

        // A raw `swift run` executable has no bundle metadata. Walk upward from
        // the executable and working directory to find the repository's app plist.
        for startingURL in developmentSearchRoots {
            if let version = findDevelopmentVersion(startingAt: startingURL) {
                return version
            }
        }

        return "development"
    }()

    private static var developmentSearchRoots: [URL] {
        var roots = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
        if let executableURL = Bundle.main.executableURL {
            roots.append(executableURL.deletingLastPathComponent())
        }
        return roots
    }

    private static func findDevelopmentVersion(startingAt startingURL: URL) -> String? {
        var directory = startingURL.standardizedFileURL

        for _ in 0..<10 {
            let plistURL = directory
                .appendingPathComponent("dist", isDirectory: true)
                .appendingPathComponent("LoopBar.app", isDirectory: true)
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Info.plist")

            if let version = version(in: plistURL) {
                return version
            }

            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { break }
            directory = parent
        }
        return nil
    }

    private static func version(in plistURL: URL) -> String? {
        guard
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ),
            let dictionary = plist as? [String: Any]
        else {
            return nil
        }

        return normalized(dictionary["CFBundleShortVersionString"] as? String)
    }

    private static func normalized(_ version: String?) -> String? {
        guard let version else { return nil }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
