import Foundation

enum AppVersion {
    /// Used only when running the executable directly with SwiftPM, where there is no app Info.plist.
    private static let developmentFallback = "0.2.0-beta"

    static let current: String = {
        let bundledVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        let trimmedVersion = bundledVersion?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let trimmedVersion, !trimmedVersion.isEmpty else {
            return developmentFallback
        }
        return trimmedVersion
    }()
}
