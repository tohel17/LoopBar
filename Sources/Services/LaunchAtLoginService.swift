import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var errorMessage: String?

    private let service: SMAppService

    var isAvailable: Bool {
        Self.isPackagedApp && status != .notFound
    }

    var isEnabled: Bool {
        Self.isEnabled(status: status)
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    var availabilityMessage: String? {
        if !Self.isPackagedApp {
            return "Launch at Login is available in the packaged LoopBar app."
        }
        if status == .notFound {
            return "macOS could not find LoopBar's login item registration."
        }
        return nil
    }

    init(service: SMAppService = .mainApp) {
        self.service = service
        status = Self.isPackagedApp ? service.status : .notFound
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
        status = Self.isPackagedApp ? service.status : .notFound
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func isEnabled(status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    private static var isPackagedApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}
