import Observation
import ServiceManagement

/// "Launch at login" via `SMAppService.mainApp`. Never registers on its own.
@MainActor
@Observable
public final class LaunchAtLogin {
    public private(set) var status: SMAppService.Status
    public private(set) var lastError: String?

    public init() {
        status = SMAppService.mainApp.status
    }

    public var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    public var requiresApproval: Bool {
        status == .requiresApproval
    }

    public func refresh() {
        status = SMAppService.mainApp.status
    }

    public func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
