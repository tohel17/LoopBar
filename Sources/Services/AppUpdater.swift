import AppKit
import Foundation
import Sparkle

/// Owns Sparkle's standard updater and exposes the small surface used by
/// LoopBar's SwiftUI settings. Sparkle persists its preferences itself.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    private let controller: SPUStandardUpdaterController
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

    private init() {
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
        controller.checkForUpdates(nil)
    }
}
