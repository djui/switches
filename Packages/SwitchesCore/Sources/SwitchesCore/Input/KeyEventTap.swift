import CoreGraphics
import Foundation
import Synchronization

public struct KeyEvent: Sendable, Equatable {
    public let keyCode: UInt16
    public let isDown: Bool
    public let isRepeat: Bool

    public init(keyCode: UInt16, isDown: Bool, isRepeat: Bool = false) {
        self.keyCode = keyCode
        self.isDown = isDown
        self.isRepeat = isRepeat
    }
}

/// Listen-only `CGEvent` tap for key down/up and modifier changes.
///
/// Runs on its own thread with a dedicated run loop; `handler` is called on that thread.
/// Requires Input Monitoring permission (not Accessibility). Never sees key characters,
/// only virtual key codes.
public final class KeyEventTap: @unchecked Sendable {
    public typealias Handler = @Sendable (KeyEvent) -> Void

    private struct Running: @unchecked Sendable {
        let port: CFMachPort
        let runLoop: CFRunLoop
    }

    private let handler: Handler
    private let running = Mutex<Running?>(nil)
    // Tap-thread state, published before the thread starts.
    private var port: CFMachPort?
    private var pressedModifiers: Set<UInt16> = []

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    public var isRunning: Bool {
        running.withLock { $0 != nil }
    }

    /// Returns `false` if the tap could not be created (usually missing permission).
    @discardableResult
    public func start() -> Bool {
        if isRunning { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: keyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.port = port
        pressedModifiers = []
        let box = UncheckedBox(port)
        let ready = DispatchSemaphore(value: 0)
        let handoff = RunLoopHandoff()

        let thread = Thread {
            let runLoop = CFRunLoopGetCurrent()!
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, box.value, 0)
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: box.value, enable: true)
            handoff.runLoop = runLoop
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "Switches.KeyEventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()

        guard let runLoop = handoff.runLoop else { return false }
        running.withLock { $0 = Running(port: port, runLoop: runLoop) }
        return true
    }

    public func stop() {
        guard let current = running.withLock({ state -> Running? in
            defer { state = nil }
            return state
        }) else { return }
        CGEvent.tapEnable(tap: current.port, enable: false)
        CFMachPortInvalidate(current.port)
        CFRunLoopStop(current.runLoop)
    }

    // MARK: Tap thread

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
        case .keyDown, .keyUp:
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            handler(KeyEvent(keyCode: keyCode, isDown: type == .keyDown, isRepeat: isRepeat))
        case .flagsChanged:
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            guard let isDown = modifierIsDown(keyCode: keyCode, flags: event.flags) else { return }
            handler(KeyEvent(keyCode: keyCode, isDown: isDown))
        default:
            break
        }
    }

    /// Device-dependent modifier bits (IOKit `NX_DEVICE*KEYMASK`) distinguish left/right keys.
    static let deviceModifierMasks: [UInt16: UInt64] = [
        59: 0x0000_0001, // Control
        56: 0x0000_0002, // Shift
        60: 0x0000_0004, // Right shift
        55: 0x0000_0008, // Command
        54: 0x0000_0010, // Right command
        58: 0x0000_0020, // Option
        61: 0x0000_0040, // Right option
        62: 0x0000_2000, // Right control
    ]

    private func modifierIsDown(keyCode: UInt16, flags: CGEventFlags) -> Bool? {
        if keyCode == 57 { return true } // Caps lock reports one event per press.
        let isDown: Bool
        if let mask = Self.deviceModifierMasks[keyCode] {
            isDown = flags.rawValue & mask != 0
        } else if keyCode == 63 {
            isDown = flags.contains(.maskSecondaryFn)
        } else {
            isDown = !pressedModifiers.contains(keyCode)
        }
        let wasDown = pressedModifiers.contains(keyCode)
        if isDown == wasDown { return nil }
        if isDown { pressedModifiers.insert(keyCode) } else { pressedModifiers.remove(keyCode) }
        return isDown
    }
}

/// Written once by the tap thread before it signals the semaphore the starter waits on.
private final class RunLoopHandoff: @unchecked Sendable {
    var runLoop: CFRunLoop?
}

private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

private func keyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo {
        Unmanaged<KeyEventTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
