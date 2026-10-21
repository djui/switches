import AppKit
import CoreGraphics
import Observation

/// Input Monitoring permission, required for the listen-only keyboard event tap.
@MainActor
@Observable
public final class PermissionManager {
    public private(set) var isGranted: Bool

    public init() {
        isGranted = CGPreflightListenEventAccess()
    }

    @discardableResult
    public func refresh() -> Bool {
        let granted = CGPreflightListenEventAccess()
        if granted != isGranted { isGranted = granted }
        return granted
    }

    /// Shows the system prompt the first time; afterwards the user must use System Settings.
    public func request() {
        _ = CGRequestListenEventAccess()
        refresh()
    }

    public func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}
