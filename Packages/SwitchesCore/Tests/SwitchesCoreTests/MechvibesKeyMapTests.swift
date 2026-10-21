import Carbon.HIToolbox
import Foundation
import Testing
@testable import SwitchesCore

struct MechvibesKeyMapTests {
    @Test(arguments: [
        (1, kVK_Escape), (2, kVK_ANSI_1), (11, kVK_ANSI_0), (12, kVK_ANSI_Minus), (13, kVK_ANSI_Equal),
        (14, kVK_Delete), (15, kVK_Tab), (16, kVK_ANSI_Q), (25, kVK_ANSI_P), (26, kVK_ANSI_LeftBracket),
        (27, kVK_ANSI_RightBracket), (28, kVK_Return), (29, kVK_Control), (30, kVK_ANSI_A), (38, kVK_ANSI_L),
        (39, kVK_ANSI_Semicolon), (40, kVK_ANSI_Quote), (41, kVK_ANSI_Grave), (42, kVK_Shift),
        (43, kVK_ANSI_Backslash), (44, kVK_ANSI_Z), (50, kVK_ANSI_M), (51, kVK_ANSI_Comma),
        (52, kVK_ANSI_Period), (53, kVK_ANSI_Slash), (54, kVK_RightShift), (56, kVK_Option),
        (57, kVK_Space), (58, kVK_CapsLock), (59, kVK_F1), (68, kVK_F10), (87, kVK_F11), (88, kVK_F12),
        (3640, kVK_RightOption), (3675, kVK_Command), (3676, kVK_RightCommand),
        (57416, kVK_UpArrow), (57419, kVK_LeftArrow), (57421, kVK_RightArrow), (57424, kVK_DownArrow),
    ])
    func knownMappings(mechvibesID: Int, keyCode: Int) {
        #expect(MechvibesKeyMap.keyCode(forMechvibesID: mechvibesID) == UInt16(keyCode))
    }

    @Test func letterRowsMapToDistinctKeys() {
        let letters = (16...25).map { $0 } + (30...38).map { $0 } + (44...50).map { $0 }
        let codes = letters.compactMap { MechvibesKeyMap.keyCode(forMechvibesID: $0) }
        #expect(codes.count == 26)
        #expect(Set(codes).count == 26)
    }

    @Test func unknownIDReturnsNil() {
        #expect(MechvibesKeyMap.keyCode(forMechvibesID: 9999) == nil)
    }

    /// The convert script parses the source table; keep it in sync with the compiled one.
    @Test func sourceTableIsParseable() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SwitchesCore/Input/MechvibesKeyMap.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        guard
            let begin = text.range(of: "// BEGIN MECHVIBES TABLE"),
            let end = text.range(of: "// END MECHVIBES TABLE")
        else {
            Issue.record("Table markers missing")
            return
        }
        var parsed: [Int: UInt16] = [:]
        for line in text[begin.upperBound..<end.lowerBound].split(separator: "\n") {
            let entry = line.split(separator: "//").first ?? ""
            let parts = entry.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces.union(.init(charactersIn: ","))) }
            guard parts.count == 2, let id = Int(parts[0]), let code = UInt16(parts[1]) else { continue }
            parsed[id] = code
        }
        #expect(parsed == MechvibesKeyMap.table)
    }
}
