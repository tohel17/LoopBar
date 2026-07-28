import Foundation
import UserNotifications

enum NotificationLogo {
    static let attachmentIdentifier = "loopbar.logo"
    private static let resourceName = "NotificationLogo"
    private static let resourceExtension = "png"

    /// Builds a notification attachment from a readable image file URL.
    /// Returns nil when the file is missing or UserNotifications rejects it.
    static func makeAttachment(from url: URL) -> UNNotificationAttachment? {
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return try? UNNotificationAttachment(
            identifier: attachmentIdentifier,
            url: url,
            options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]
        )
    }

    /// Resolves the bundled logo and copies it to a temp URL so UNNotificationAttachment
    /// can take ownership without deleting the app resource.
    static func makeBundledAttachment(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> UNNotificationAttachment? {
        guard let source = resourceURL(in: bundle) else { return nil }

        let temp = fileManager.temporaryDirectory
            .appendingPathComponent("loopbar-notification-logo-\(UUID().uuidString).png")
        do {
            if fileManager.fileExists(atPath: temp.path) {
                try fileManager.removeItem(at: temp)
            }
            try fileManager.copyItem(at: source, to: temp)
            return makeAttachment(from: temp)
        } catch {
            return nil
        }
    }

    static func resourceURL(in bundle: Bundle) -> URL? {
        if let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) {
            return url
        }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: resourceName, withExtension: resourceExtension) {
            return url
        }
        #endif
        return nil
    }
}
