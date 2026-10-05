import XCTest
import Sparkle
@testable import VaultoNote

final class UpdateTests: XCTestCase {
    func testInitialUpdateChoiceDoesNotRequireSecondRestartConfirmation() {
        let driver = OneClickUpdateDriver(hostBundle: .main, delegate: nil)
        var choices: [SPUUserUpdateChoice] = []
        driver.showReady(toInstallAndRelaunch: { choices.append($0) })
        XCTAssertEqual(choices, [.install])
    }

    func testRecordingAndTranscribingKeepRestartPendingUntilIdle() {
        var idleActions: [() -> Void] = []
        let gate = UpdateRestartGate(scheduleIdle: { action in
            idleActions.append(action)
            return {}
        })
        var restarts = 0
        gate.isBusy = true
        XCTAssertTrue(gate.postpone { restarts += 1 })
        gate.isBusy = true // recording ends, transcription is still in progress
        XCTAssertEqual(restarts, 0)
        gate.isBusy = false
        XCTAssertEqual(restarts, 0) // paste and clipboard restoration still have time to finish
        idleActions.removeFirst()()
        XCTAssertEqual(restarts, 1)
        gate.isBusy = false
        idleActions.removeFirst()()
        XCTAssertEqual(restarts, 1)
    }

    func testIdleApplicationLetsSparkleRestartImmediately() {
        let gate = UpdateRestartGate()
        XCTAssertFalse(gate.postpone { XCTFail("Sparkle should handle this restart") })
    }

    func testCanceledUpdateDoesNotRestartWhenDictationFinishes() {
        var idleAction: (() -> Void)?
        let gate = UpdateRestartGate(scheduleIdle: { action in idleAction = action; return {} })
        gate.isBusy = true
        XCTAssertTrue(gate.postpone { XCTFail("Canceled update must not restart") })
        gate.cancel()
        gate.isBusy = false
        idleAction?()
    }

    func testNewRecordingCancelsRestartDuringClipboardSettling() {
        var idleActions: [() -> Void] = []
        let gate = UpdateRestartGate(scheduleIdle: { action in idleActions.append(action); return {} })
        var restarts = 0
        gate.isBusy = true
        XCTAssertTrue(gate.postpone { restarts += 1 })
        gate.isBusy = false
        gate.isBusy = true // another dictation starts before the quiet second ends
        idleActions.removeFirst()() // even a canceled callback must be harmless
        XCTAssertEqual(restarts, 0)
        gate.isBusy = false
        idleActions.removeFirst()()
        XCTAssertEqual(restarts, 1)
    }

    func testUpdateArrivingAfterDictationStillWaitsForClipboardSettling() {
        var idleAction: (() -> Void)?
        let gate = UpdateRestartGate(scheduleIdle: { action in idleAction = action; return {} })
        var restarts = 0
        gate.isBusy = true
        gate.isBusy = false
        XCTAssertTrue(gate.postpone { restarts += 1 })
        XCTAssertEqual(restarts, 0)
        idleAction?()
        XCTAssertEqual(restarts, 1)
    }
}
