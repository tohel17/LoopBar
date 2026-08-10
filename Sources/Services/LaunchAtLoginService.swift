import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var errorMessage: String?

    private let service: SMAppService
    private let packagedApp: Bool
    private let transientLocation: Bool

    var isAvailable: Bool {
        Self.isAvailable(
            isPackagedApp: packagedApp,
            isRunningFromTransientLocation: transientLocation
        )
    }

    var isEnabled: Bool {
        Self.isEnabled(status: status)
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    var availabilityMessage: String? {
        if !packagedApp {
            return "Launch at Login is available in the packaged LoopBar app."
        }
        if transientLocation {
            return "Drag LoopBar to Applications and open it there before enabling Launch at Login."
        }
        if status == .notFound {
            return "macOS has not found LoopBar's login item yet. Turn this on to retry registration."
        }
        return nil
    }

    init(service: SMAppService = .mainApp, bundleURL: URL = Bundle.main.bundleURL) {
        let isPackagedApp = Self.isPackagedApp(bundleURL: bundleURL)
        let isTransientLocation = Self.isRunningFromTransientLocation(bundleURL: bundleURL)

        self.service = service
        packagedApp = isPackagedApp
        transientLocation = isTransientLocation
        status = isPackagedApp ? service.status : .notFound
    }

    func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        guard enabled != isEnabled else { return }

        errorMessage = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
        if enabled == isEnabled {
            errorMessage = nil
        }
    }

    func refresh() {
        status = packagedApp ? service.status : .notFound
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func isEnabled(status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    static func isAvailable(
        isPackagedApp: Bool,
        isRunningFromTransientLocation: Bool
    ) -> Bool {
        isPackagedApp && !isRunningFromTransientLocation
    }

    static func isTransientPath(_ path: String) -> Bool {
        path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }

    private static func isPackagedApp(bundleURL: URL) -> Bool {
        bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    private static func isRunningFromTransientLocation(bundleURL: URL) -> Bool {
        if isTransientPath(bundleURL.path) {
            return true
        }

        let values = try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        return values?.volumeIsReadOnly == true
    }
}
