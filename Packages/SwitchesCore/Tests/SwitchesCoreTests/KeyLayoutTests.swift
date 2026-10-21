import Carbon.HIToolbox
import Testing
@testable import SwitchesCore

struct KeyLayoutTests {
    let layout = KeyLayout(kind: .ansi)

    @Test func leftKeysPanLeftAndRightKeysPanRight() {
        #expect(layout.info(for: UInt16(kVK_ANSI_Q)).pan < -0.5)
        #expect(layout.info(for: UInt16(kVK_ANSI_P)).pan > 0.3)
        #expect(layout.info(for: UInt16(kVK_Return)).pan > 0.8)
        #expect(layout.info(for: UInt16(kVK_Escape)).pan == -1)
    }

    @Test func spaceIsNearCenter() {
        #expect(abs(layout.info(for: UInt16(kVK_Space)).pan) < 0.1)
    }

    @Test func panIsAlwaysInRange() {
        for code in UInt16(0)...UInt16(127) {
            let pan = layout.info(for: code).pan
            #expect((-1...1).contains(pan))
        }
    }

    @Test func groups() {
        #expect(KeyLayout.group(for: UInt16(kVK_Space)) == .space)
        #expect(KeyLayout.group(for: UInt16(kVK_Return)) == .enter)
        #expect(KeyLayout.group(for: UInt16(kVK_ANSI_KeypadEnter)) == .enter)
        #expect(KeyLayout.group(for: UInt16(kVK_Delete)) == .backspace)
        #expect(KeyLayout.group(for: UInt16(kVK_Shift)) == .modifier)
        #expect(KeyLayout.group(for: UInt16(kVK_RightCommand)) == .modifier)
        #expect(KeyLayout.group(for: UInt16(kVK_ANSI_A)) == .alpha)
    }

    @Test func rows() {
        #expect(layout.info(for: UInt16(kVK_F1)).row == 0)
        #expect(layout.info(for: UInt16(kVK_ANSI_1)).row == 1)
        #expect(layout.info(for: UInt16(kVK_ANSI_A)).row == 3)
        #expect(layout.info(for: UInt16(kVK_Space)).row == 5)
    }

    @Test func isoMovesGraveNextToLeftShift() {
        let iso = KeyLayout(kind: .iso)
        #expect(iso.info(for: UInt16(kVK_ANSI_Grave)).row == 4)
        #expect(iso.info(for: UInt16(kVK_ISO_Section)).row == 1)
        #expect(layout.info(for: UInt16(kVK_ANSI_Grave)).row == 1)
    }

    @Test func jisHasYenAndKanaKeys() {
        let jis = KeyLayout(kind: .jis)
        #expect(jis.info(for: UInt16(kVK_JIS_Yen)).pan > 0.5)
        #expect(jis.info(for: UInt16(kVK_JIS_Eisu)).pan < 0)
        #expect(jis.info(for: UInt16(kVK_JIS_Kana)).pan > 0)
    }
}
