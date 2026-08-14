import AppKit
import Foundation
import Sparkle

/// Owns Sparkle's standard updater and exposes the small surface used by
/// LoopBar's SwiftUI settings. Sparkle persists its preferences itself.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    private let controller: SPUStandardUpdaterController
    private let bundleURL: URL
    private(set) var isStarted = false

    var isAvailable: Bool {
        guard
            let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            !feedURL.isEmpty,
            let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            !publicKey.isEmpty
        else {
            return false
        }
        return true
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue

            if newValue, controller.updater.allowsAutomaticUpdates {
                controller.updater.automaticallyDownloadsUpdates = true
            }
        }
    }

    var isInstalledInApplications: Bool {
        Self.isInstalledInApplications(bundleURL: bundleURL)
    }

    var availabilityMessage: String {
        if !isAvailable {
            return "Update checks are available in the packaged app."
        }
        if !isInstalledInApplications {
            return "Move LoopBar to Applications before checking for updates."
        }
        return "LoopBar checks once a day."
    }

    private init() {
        bundleURL = Bundle.main.bundleURL
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Sparkle must start after application launch. Raw `swift run` builds do
    /// not have LoopBar's packaged Info.plist, so updates stay unavailable.
    func start() {
        guard isAvailable, !isStarted else { return }
        controller.startUpdater()
        isStarted = true
        objectWillChange.send()
    }

    func checkForUpdates() {
        guard isAvailable, isStarted else { return }
        NSApp.activate(ignoringOtherApps: true)

        guard isInstalledInApplications else {
            offerToInstallInApplications()
            return
        }

        controller.checkForUpdates(nil)
    }

    static func isInstalledInApplications(
        bundleURL: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let bundlePath = bundleURL.standardizedFileURL.path
        let systemApplicationsPath = URL(fileURLWithPath: "/Applications", isDirectory: true).path
        let userApplicationsPath = homeDirectory
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL.path

        return isDescendant(bundlePath, of: systemApplicationsPath)
            || isDescendant(bundlePath, of: userApplicationsPath)
    }

    private static func isDescendant(_ path: String, of directory: String) -> Bool {
        path == directory || path.hasPrefix(directory + "/")
    }

    private func offerToInstallInApplications() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Move LoopBar to Applications"
        alert.informativeText = "LoopBar can’t update while it is running from Downloads, a disk image, or another temporary location. Move it to Applications, then reopen it and check again."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let installedURL = try installInApplications()
            NSWorkspace.shared.activateFileViewerSelecting([installedURL])

            let completionAlert = NSAlert()
            completionAlert.alertStyle = .informational
            completionAlert.messageText = "LoopBar is ready in Applications"
            completionAlert.informativeText = "Quit this copy, then open the selected LoopBar app from Applications. Update checks will work there."
            completionAlert.addButton(withTitle: "Quit LoopBar")
            completionAlert.addButton(withTitle: "Keep Running")
            if completionAlert.runModal() == .alertFirstButtonReturn {
                NSApp.terminate(nil)
            }
        } catch {
            let failureAlert = NSAlert(error: error)
            failureAlert.messageText = "LoopBar couldn’t be moved"
            failureAlert.informativeText = "Move LoopBar.app to your Applications folder in Finder, reopen it there, and try again.\n\n\(error.localizedDescription)"
            failureAlert.runModal()
        }
    }

    private func installInApplications(fileManager: FileManager = .default) throws -> URL {
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let userApplications = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        let destinationDirectory: URL

        if fileManager.isWritableFile(atPath: systemApplications.path) {
            destinationDirectory = systemApplications
        } else {
            try fileManager.createDirectory(
                at: userApplications,
                withIntermediateDirectories: true
            )
            destinationDirectory = userApplications
        }

        let destination = destinationDirectory.appendingPathComponent(
            bundleURL.lastPathComponent,
            isDirectory: true
        )

        // An older installed copy may already exist when the user launches a
        // freshly downloaded copy. Reopen that copy and let Sparkle update it
        // instead of replacing an application bundle that may contain data the
        // user expects to keep.
        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }

        try fileManager.copyItem(at: bundleURL, to: destination)
        return destination
    }
}
