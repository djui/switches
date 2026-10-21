import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Observation
import Synchronization

/// Lock-free pause check used on the key-tap thread.
public final class PauseGate: Sendable {
    let blocked = Atomic<Bool>(false)
    let watchSecureInput = Atomic<Bool>(true)

    public init() {}

    public func shouldDrop() -> Bool {
        if blocked.load(ordering: .relaxed) { return true }
        return watchSecureInput.load(ordering: .relaxed) && IsSecureEventInputEnabled()
    }
}

public enum PauseReason: Equatable, Sendable {
    case manual
    case excludedApp(String)
    case game(String)
    case fullscreen(String)
    case secureInput

    public var description: String {
        switch self {
        case .manual: "Paused"
        case let .excludedApp(name): "Paused in \(name)"
        case let .game(name): "Paused while playing \(name)"
        case let .fullscreen(name): "Paused while \(name) is full screen"
        case .secureInput: "Paused during secure text entry"
        }
    }
}

/// Decides when sounds are muted: manual pause / hotkey, excluded apps, games,
/// full-screen apps and secure text input.
@MainActor
@Observable
public final class PauseController {
    public static let hotkeyDescription = "⌃⌥⌘K"

    public private(set) var reason: PauseReason?
    public var isPaused: Bool { reason != nil }

    @ObservationIgnored public let gate = PauseGate()
    @ObservationIgnored private let appState: AppState
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var hotKey: GlobalHotKey?
    @ObservationIgnored private var gameCache: [String: Bool] = [:]

    public init(appState: AppState) {
        self.appState = appState
    }

    public func start() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        settingsChanged()
    }

    public func stop() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        timer?.invalidate()
        timer = nil
        hotKey?.invalidate()
        hotKey = nil
    }

    public func togglePause() {
        appState.paused.toggle()
    }

    public func settingsChanged() {
        if appState.hotkeyEnabled, hotKey == nil {
            hotKey = GlobalHotKey(
                keyCode: UInt32(kVK_ANSI_K),
                modifiers: UInt32(controlKey | optionKey | cmdKey)
            ) { [weak self] in
                self?.togglePause()
            }
        } else if !appState.hotkeyEnabled, let hotKey {
            hotKey.invalidate()
            self.hotKey = nil
        }
        gate.watchSecureInput.store(appState.pauseOnSecureInput, ordering: .relaxed)
        recompute()
    }

    public func recompute() {
        let front = NSWorkspace.shared.frontmostApplication
        let name = front?.localizedName ?? front?.bundleIdentifier ?? "app"
        let isSelf = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier

        var newReason: PauseReason?
        if appState.paused {
            newReason = .manual
        } else if let id = front?.bundleIdentifier, appState.excludedBundleIDs.contains(id) {
            newReason = .excludedApp(name)
        } else if !isSelf, appState.pauseForGames, let front, isGame(front) {
            newReason = .game(name)
        } else if !isSelf, appState.pauseInFullscreen, let front, isFullscreen(front) {
            newReason = .fullscreen(name)
        } else if appState.pauseOnSecureInput, IsSecureEventInputEnabled() {
            newReason = .secureInput
        }

        gate.blocked.store(newReason != nil && newReason != .secureInput, ordering: .relaxed)
        if newReason != reason { reason = newReason }
    }

    private func isGame(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        if let cached = gameCache[id] { return cached }
        var result = false
        if let url = app.bundleURL,
           let category = Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String {
            result = category.hasSuffix("games") || category.hasSuffix("-games")
        }
        gameCache[id] = result
        return result
    }

    private func isFullscreen(_ app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return false }
        let screenSizes = NSScreen.screens.map(\.frame.size)
        for window in windows {
            guard
                (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                (window[kCGWindowLayer as String] as? Int) == 0,
                let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            if screenSizes.contains(where: { abs($0.width - bounds.width) < 1 && abs($0.height - bounds.height) < 1 }) {
                return true
            }
        }
        return false
    }
}

/// System-wide hotkey via Carbon `RegisterEventHotKey` (works in the sandbox, consumes the key).
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    fileprivate let action: @MainActor () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installed == noErr else { return nil }
        let id = EventHotKeyID(signature: 0x5357_4348, id: 1) // 'SWCH'
        let registered = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
    }

    func invalidate() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}

private func globalHotKeyHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { hotKey.action() }
    return noErr
}
