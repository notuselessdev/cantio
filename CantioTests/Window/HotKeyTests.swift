import XCTest
import AppKit
import Carbon.HIToolbox
@testable import Cantio

final class HotKeyTests: XCTestCase {
    func test_carbonModifiers_command_mapsToCmdKey() {
        let r = HotKey.carbonModifiers(from: [.command])

        XCTAssertEqual(r, UInt32(cmdKey))
    }

    func test_carbonModifiers_option_mapsToOptionKey() {
        let r = HotKey.carbonModifiers(from: [.option])

        XCTAssertEqual(r, UInt32(optionKey))
    }

    func test_carbonModifiers_control_mapsToControlKey() {
        let r = HotKey.carbonModifiers(from: [.control])

        XCTAssertEqual(r, UInt32(controlKey))
    }

    func test_carbonModifiers_shift_mapsToShiftKey() {
        let r = HotKey.carbonModifiers(from: [.shift])

        XCTAssertEqual(r, UInt32(shiftKey))
    }

    func test_carbonModifiers_optionCommand_mapsToBoth() {
        let r = HotKey.carbonModifiers(from: [.option, .command])

        XCTAssertEqual(r, UInt32(optionKey) | UInt32(cmdKey))
    }

    func test_carbonModifiers_unrelatedFlags_areIgnored() {
        let r = HotKey.carbonModifiers(from: [.capsLock, .numericPad])

        XCTAssertEqual(r, 0)
    }

    func test_displayString_defaultToggle_isOptionCommandL() {
        let s = HotKey.defaultToggle.displayString

        XCTAssertEqual(s, "⌥⌘L")
    }

    func test_displayString_commandL_isCommandL() {
        let hk = HotKey(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey))

        XCTAssertEqual(hk.displayString, "⌘L")
    }

    func test_displayString_shiftCommandQ_isShiftCommandQ() {
        let hk = HotKey(keyCode: UInt32(kVK_ANSI_Q),
                        modifiers: UInt32(cmdKey | shiftKey))

        XCTAssertEqual(hk.displayString, "⇧⌘Q")
    }

    func test_displayString_modifierOrder_isControlOptionShiftCommand() {
        let hk = HotKey(keyCode: UInt32(kVK_ANSI_A),
                        modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))

        XCTAssertTrue(hk.displayString.hasPrefix("⌃⌥⇧⌘"), hk.displayString)
    }

    func test_keyName_F5_returnsF5() {
        XCTAssertEqual(HotKey.keyName(for: UInt32(kVK_F5)), "F5")
    }

    func test_keyName_leftArrow_returnsArrow() {
        XCTAssertEqual(HotKey.keyName(for: UInt32(kVK_LeftArrow)), "←")
    }

    func test_initEventModifiers_command_storesCarbonCmdKey() {
        let hk = HotKey(keyCode: UInt16(kVK_ANSI_L), eventModifiers: [.command])

        XCTAssertEqual(hk.modifiers, UInt32(cmdKey))
        XCTAssertEqual(hk.keyCode, UInt32(kVK_ANSI_L))
    }
}
