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

        // A raw `swift run` executable has no app Info.plist, so SwiftPM's
        // generated resource bundle is the reliable source in development.
        if
            let versionURL = Bundle.module.url(
                forResource: "version",
                withExtension: "txt"
            ),
            let version = try? String(contentsOf: versionURL, encoding: .utf8),
            let normalizedVersion = normalized(version)
        {
            return normalizedVersion
        }

        return "development"
    }()

    private static func normalized(_ version: String?) -> String? {
        guard let version else { return nil }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
