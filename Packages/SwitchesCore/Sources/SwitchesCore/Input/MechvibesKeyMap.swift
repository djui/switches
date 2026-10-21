/// Mechvibes key IDs (libuiohook scancodes) → macOS virtual key codes (`CGKeyCode`).
///
/// Only used when converting raw packs and in tests; the app works with `CGKeyCode` only.
/// `scripts/convert_sounds.swift` parses the table between the BEGIN/END markers, so keep
/// exactly one `id: keyCode,` entry per line there.
public enum MechvibesKeyMap {
    public static let table: [Int: UInt16] = [
        // BEGIN MECHVIBES TABLE
        1: 53, // Escape
        2: 18, // 1
        3: 19, // 2
        4: 20, // 3
        5: 21, // 4
        6: 23, // 5
        7: 22, // 6
        8: 26, // 7
        9: 28, // 8
        10: 25, // 9
        11: 29, // 0
        12: 27, // Minus
        13: 24, // Equal
        14: 51, // Delete (Backspace)
        15: 48, // Tab
        16: 12, // Q
        17: 13, // W
        18: 14, // E
        19: 15, // R
        20: 17, // T
        21: 16, // Y
        22: 32, // U
        23: 34, // I
        24: 31, // O
        25: 35, // P
        26: 33, // Left bracket
        27: 30, // Right bracket
        28: 36, // Return
        29: 59, // Control
        30: 0, // A
        31: 1, // S
        32: 2, // D
        33: 3, // F
        34: 5, // G
        35: 4, // H
        36: 38, // J
        37: 40, // K
        38: 37, // L
        39: 41, // Semicolon
        40: 39, // Quote
        41: 50, // Grave
        42: 56, // Shift
        43: 42, // Backslash
        44: 6, // Z
        45: 7, // X
        46: 8, // C
        47: 9, // V
        48: 11, // B
        49: 45, // N
        50: 46, // M
        51: 43, // Comma
        52: 47, // Period
        53: 44, // Slash
        54: 60, // Right shift
        55: 67, // Keypad multiply
        56: 58, // Option (Alt)
        57: 49, // Space
        58: 57, // Caps lock
        59: 122, // F1
        60: 120, // F2
        61: 99, // F3
        62: 118, // F4
        63: 96, // F5
        64: 97, // F6
        65: 98, // F7
        66: 100, // F8
        67: 101, // F9
        68: 109, // F10
        69: 71, // Num lock → keypad clear
        70: 107, // Scroll lock → F14
        71: 89, // Keypad 7
        72: 91, // Keypad 8
        73: 92, // Keypad 9
        74: 78, // Keypad minus
        75: 86, // Keypad 4
        76: 87, // Keypad 5
        77: 88, // Keypad 6
        78: 69, // Keypad plus
        79: 83, // Keypad 1
        80: 84, // Keypad 2
        81: 85, // Keypad 3
        82: 82, // Keypad 0
        83: 65, // Keypad decimal
        87: 103, // F11
        88: 111, // F12
        91: 105, // F13
        92: 107, // F14
        93: 113, // F15
        3612: 76, // Keypad enter
        3613: 62, // Right control
        3637: 75, // Keypad divide
        3639: 105, // Print screen → F13
        3640: 61, // Right option (AltGr)
        3653: 113, // Pause → F15
        3655: 115, // Home
        3657: 116, // Page up
        3663: 119, // End
        3665: 121, // Page down
        3666: 114, // Insert → Help
        3667: 117, // Forward delete
        3675: 55, // Command (left meta)
        3676: 54, // Right command (right meta)
        3677: 110, // Context menu
        57416: 126, // Up arrow
        57419: 123, // Left arrow
        57421: 124, // Right arrow
        57424: 125, // Down arrow
        60999: 115, // Home (extended)
        61000: 126, // Up arrow (extended)
        61001: 116, // Page up (extended)
        61003: 123, // Left arrow (extended)
        61005: 124, // Right arrow (extended)
        61007: 119, // End (extended)
        61008: 125, // Down arrow (extended)
        61009: 121, // Page down (extended)
        61010: 114, // Insert (extended) → Help
        61011: 117, // Forward delete (extended)
        // END MECHVIBES TABLE
    ]

    public static func keyCode(forMechvibesID id: Int) -> UInt16? {
        table[id]
    }
}
