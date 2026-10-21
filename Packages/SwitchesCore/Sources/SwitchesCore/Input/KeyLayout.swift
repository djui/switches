import Carbon.HIToolbox

public enum KeyGroup: String, Codable, Sendable, CaseIterable {
    case alpha, space, enter, backspace, modifier
}

public enum KeyboardLayoutKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case ansi, iso, jis

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ansi: "ANSI (US)"
        case .iso: "ISO (Europe)"
        case .jis: "JIS (Japan)"
        }
    }

    /// Physical layout of the built-in / last used keyboard as reported by the system.
    public static func detectSystem() -> KeyboardLayoutKind {
        switch Int(KBGetLayoutType(Int16(LMGetKbdType()))) {
        case kKeyboardISO: .iso
        case kKeyboardJIS: .jis
        default: .ansi
        }
    }
}

public struct KeyInfo: Sendable, Equatable {
    /// -1 (far left) ... 1 (far right).
    public let pan: Float
    /// 0 = function row, 5 = space bar row.
    public let row: Int
    public let group: KeyGroup
}

/// Maps macOS virtual key codes (`CGKeyCode`) to their physical position on a Mac keyboard.
public struct KeyLayout: Sendable {
    public let kind: KeyboardLayoutKind
    private let table: [UInt16: KeyInfo]

    /// Horizontal key-unit center and half-width of the main key block.
    static let centerX = 7.5
    static let halfWidth = 7.0

    public init(kind: KeyboardLayoutKind = .ansi) {
        self.kind = kind
        var positions = Self.ansi
        switch kind {
        case .ansi: break
        case .iso: positions.merge(Self.isoOverrides) { $1 }
        case .jis: positions.merge(Self.jisOverrides) { $1 }
        }
        var table: [UInt16: KeyInfo] = [:]
        for (code, position) in positions {
            let pan = min(max((position.x - Self.centerX) / Self.halfWidth, -1), 1)
            table[code] = KeyInfo(pan: Float(pan), row: position.row, group: Self.group(for: code))
        }
        self.table = table
    }

    public func info(for keyCode: UInt16) -> KeyInfo {
        table[keyCode] ?? KeyInfo(pan: 0, row: 3, group: Self.group(for: keyCode))
    }

    public static func group(for keyCode: UInt16) -> KeyGroup {
        switch Int(keyCode) {
        case kVK_Space: .space
        case kVK_Return, kVK_ANSI_KeypadEnter: .enter
        case kVK_Delete, kVK_ForwardDelete: .backspace
        case kVK_Shift, kVK_RightShift, kVK_Control, kVK_RightControl, kVK_Option, kVK_RightOption,
             kVK_Command, kVK_RightCommand, kVK_CapsLock, kVK_Function:
            .modifier
        default: .alpha
        }
    }

    struct Position {
        let row: Int
        let x: Double
    }

    private static func row(_ row: Int, _ keys: [(Int, Double)]) -> [UInt16: Position] {
        Dictionary(uniqueKeysWithValues: keys.map { (UInt16($0.0), Position(row: row, x: $0.1)) })
    }

    /// Mac laptop ANSI geometry in key units (center of each key).
    static let ansi: [UInt16: Position] = {
        var p: [UInt16: Position] = [:]
        let rows: [[UInt16: Position]] = [
            row(0, [
                (kVK_Escape, 0.5), (kVK_F1, 1.6), (kVK_F2, 2.7), (kVK_F3, 3.8), (kVK_F4, 4.9),
                (kVK_F5, 6.0), (kVK_F6, 7.1), (kVK_F7, 8.2), (kVK_F8, 9.3), (kVK_F9, 10.4),
                (kVK_F10, 11.5), (kVK_F11, 12.6), (kVK_F12, 13.7),
                (kVK_F13, 15.7), (kVK_F14, 16.7), (kVK_F15, 17.7), (kVK_F16, 19.0),
                (kVK_F17, 20.0), (kVK_F18, 21.0), (kVK_F19, 22.0), (kVK_F20, 22.5),
            ]),
            row(1, [
                (kVK_ANSI_Grave, 0.5), (kVK_ANSI_1, 1.5), (kVK_ANSI_2, 2.5), (kVK_ANSI_3, 3.5),
                (kVK_ANSI_4, 4.5), (kVK_ANSI_5, 5.5), (kVK_ANSI_6, 6.5), (kVK_ANSI_7, 7.5),
                (kVK_ANSI_8, 8.5), (kVK_ANSI_9, 9.5), (kVK_ANSI_0, 10.5), (kVK_ANSI_Minus, 11.5),
                (kVK_ANSI_Equal, 12.5), (kVK_Delete, 14.0),
                (kVK_Help, 15.7), (kVK_Home, 16.7), (kVK_PageUp, 17.7),
                (kVK_ANSI_KeypadClear, 19.0), (kVK_ANSI_KeypadEquals, 20.0),
                (kVK_ANSI_KeypadDivide, 21.0), (kVK_ANSI_KeypadMultiply, 22.0),
            ]),
            row(2, [
                (kVK_Tab, 0.75), (kVK_ANSI_Q, 2.0), (kVK_ANSI_W, 3.0), (kVK_ANSI_E, 4.0),
                (kVK_ANSI_R, 5.0), (kVK_ANSI_T, 6.0), (kVK_ANSI_Y, 7.0), (kVK_ANSI_U, 8.0),
                (kVK_ANSI_I, 9.0), (kVK_ANSI_O, 10.0), (kVK_ANSI_P, 11.0),
                (kVK_ANSI_LeftBracket, 12.0), (kVK_ANSI_RightBracket, 13.0), (kVK_ANSI_Backslash, 14.25),
                (kVK_ForwardDelete, 15.7), (kVK_End, 16.7), (kVK_PageDown, 17.7),
                (kVK_ANSI_Keypad7, 19.0), (kVK_ANSI_Keypad8, 20.0), (kVK_ANSI_Keypad9, 21.0),
                (kVK_ANSI_KeypadMinus, 22.0),
            ]),
            row(3, [
                (kVK_CapsLock, 0.9), (kVK_ANSI_A, 2.25), (kVK_ANSI_S, 3.25), (kVK_ANSI_D, 4.25),
                (kVK_ANSI_F, 5.25), (kVK_ANSI_G, 6.25), (kVK_ANSI_H, 7.25), (kVK_ANSI_J, 8.25),
                (kVK_ANSI_K, 9.25), (kVK_ANSI_L, 10.25), (kVK_ANSI_Semicolon, 11.25),
                (kVK_ANSI_Quote, 12.25), (kVK_Return, 13.9),
                (kVK_ANSI_Keypad4, 19.0), (kVK_ANSI_Keypad5, 20.0), (kVK_ANSI_Keypad6, 21.0),
                (kVK_ANSI_KeypadPlus, 22.0),
            ]),
            row(4, [
                (kVK_Shift, 1.1), (kVK_ANSI_Z, 2.75), (kVK_ANSI_X, 3.75), (kVK_ANSI_C, 4.75),
                (kVK_ANSI_V, 5.75), (kVK_ANSI_B, 6.75), (kVK_ANSI_N, 7.75), (kVK_ANSI_M, 8.75),
                (kVK_ANSI_Comma, 9.75), (kVK_ANSI_Period, 10.75), (kVK_ANSI_Slash, 11.75),
                (kVK_RightShift, 13.6),
                (kVK_ANSI_Keypad1, 19.0), (kVK_ANSI_Keypad2, 20.0), (kVK_ANSI_Keypad3, 21.0),
                (kVK_ANSI_KeypadEnter, 22.0),
            ]),
            row(5, [
                (kVK_Function, 0.5), (kVK_Control, 1.5), (kVK_Option, 2.5), (kVK_Command, 3.75),
                (kVK_Space, 7.0), (kVK_RightCommand, 10.25), (kVK_RightOption, 11.4),
                (kVK_RightControl, 11.9),
                (kVK_LeftArrow, 12.5), (kVK_UpArrow, 13.5), (kVK_DownArrow, 13.5), (kVK_RightArrow, 14.5),
                (kVK_ANSI_Keypad0, 19.5), (kVK_ANSI_KeypadDecimal, 21.0),
                (kVK_ContextualMenu, 12.0),
            ]),
        ]
        for r in rows { p.merge(r) { $1 } }
        return p
    }()

    /// ISO: § top-left, ` next to a shorter left shift, \ moves next to the tall return.
    static let isoOverrides: [UInt16: Position] = [
        UInt16(kVK_ISO_Section): Position(row: 1, x: 0.5),
        UInt16(kVK_ANSI_Grave): Position(row: 4, x: 1.75),
        UInt16(kVK_Shift): Position(row: 4, x: 0.6),
        UInt16(kVK_ANSI_Backslash): Position(row: 3, x: 13.25),
        UInt16(kVK_Return): Position(row: 2, x: 14.1),
    ]

    /// JIS: ¥ and _ keys, 英数 / かな around a narrower space bar.
    static let jisOverrides: [UInt16: Position] = [
        UInt16(kVK_JIS_Yen): Position(row: 1, x: 13.0),
        UInt16(kVK_Delete): Position(row: 1, x: 14.25),
        UInt16(kVK_JIS_Underscore): Position(row: 4, x: 12.75),
        UInt16(kVK_RightShift): Position(row: 4, x: 14.0),
        UInt16(kVK_ANSI_Backslash): Position(row: 3, x: 13.0),
        UInt16(kVK_Return): Position(row: 2, x: 14.1),
        UInt16(kVK_JIS_Eisu): Position(row: 5, x: 4.9),
        UInt16(kVK_JIS_Kana): Position(row: 5, x: 9.3),
        UInt16(kVK_JIS_KeypadComma): Position(row: 5, x: 20.0),
    ]
}
