import XCTest
@testable import VaultoNote

final class HotkeyMonitorTests: XCTestCase {
    private var monitor: HotkeyMonitor!
    private var events: [String] = []
    private var clock = Date(timeIntervalSince1970: 0)

    override func setUp() {
        monitor = HotkeyMonitor()
        events = []
        monitor.now = { [unowned self] in clock }
        monitor.onStart = { [unowned self] in events.append("start") }
        monitor.onStop = { [unowned self] in events.append("stop") }
        monitor.onCancel = { [unowned self] in events.append("cancel") }
    }

    private func press(holding seconds: TimeInterval) {
        monitor.triggerDown()
        clock += seconds
        monitor.triggerUp()
    }

    // MARK: Hold or tap

    func testHybridHoldTalksWhileHeld() {
        monitor.mode = .hybrid
        press(holding: 2)
        XCTAssertEqual(events, ["start", "stop"])
    }

    func testHybridTapStartsHandsFreeAndNextPressStops() {
        monitor.mode = .hybrid
        press(holding: 0.1)
        XCTAssertEqual(events, ["start"], "a tap keeps recording")
        clock += 5
        monitor.triggerDown()
        XCTAssertEqual(events, ["start", "stop"])
        monitor.triggerUp()
        XCTAssertEqual(events, ["start", "stop"], "release after stopping does nothing")
    }

    func testHybridLetterWhileHeldCancels() {
        monitor.shortcut = .modifier(.rightOption)
        monitor.mode = .hybrid
        monitor.triggerDown()
        monitor.otherKeyDown(0) // ⌥A typed a character
        monitor.triggerUp()
        XCTAssertEqual(events, ["start", "cancel"])
    }

    func testTypingDuringHandsFreeDoesNotCancel() {
        monitor.mode = .hybrid
        press(holding: 0.1)
        monitor.otherKeyDown(0)
        XCTAssertEqual(events, ["start"])
    }

    // MARK: Hold only

    func testHoldShortTapIsIgnored() {
        monitor.mode = .hold
        press(holding: 0.1)
        XCTAssertEqual(events, ["start", "cancel"])
    }

    func testHoldLongPressStops() {
        monitor.mode = .hold
        press(holding: 1)
        XCTAssertEqual(events, ["start", "stop"])
    }

    // MARK: Toggle

    func testToggleStartsAndStopsOnPresses() {
        monitor.mode = .toggle
        press(holding: 0.1)
        XCTAssertEqual(events, ["start"])
        press(holding: 3)
        XCTAssertEqual(events, ["start", "stop"])
    }

    // MARK: Escape

    func testEscapeCancelsHandsFree() {
        monitor.mode = .hybrid
        press(holding: 0.1)
        monitor.otherKeyDown(53)
        XCTAssertEqual(events, ["start", "cancel"])
        monitor.triggerDown()
        XCTAssertEqual(events, ["start", "cancel", "start"], "next press starts a new recording")
    }

    func testEscapeDisabledKeepsRecording() {
        monitor.mode = .toggle
        monitor.cancelWithEscape = false
        press(holding: 0.1)
        monitor.otherKeyDown(53)
        XCTAssertEqual(events, ["start"])
    }

    func testEscapeWhenIdleDoesNothing() {
        monitor.otherKeyDown(53)
        XCTAssertEqual(events, [])
    }

    // MARK: External control

    func testMenuStartedRecordingStopsOnNextPress() {
        monitor.lock()
        monitor.triggerDown()
        XCTAssertEqual(events, ["stop"])
    }

    func testResetAfterFailedStart() {
        monitor.mode = .hybrid
        monitor.triggerDown()
        monitor.reset() // e.g. model not ready
        monitor.triggerUp()
        XCTAssertEqual(events, ["start"], "release after reset must not report stop")
    }
}
