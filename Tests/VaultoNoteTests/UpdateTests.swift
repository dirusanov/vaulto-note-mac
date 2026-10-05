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
        let gate = UpdateRestartGate()
        var restarts = 0
        gate.isBusy = true
        XCTAssertTrue(gate.postpone { restarts += 1 })
        gate.isBusy = true // recording ends, transcription is still in progress
        XCTAssertEqual(restarts, 0)
        gate.isBusy = false
        XCTAssertEqual(restarts, 1)
        gate.isBusy = false
        XCTAssertEqual(restarts, 1)
    }

    func testIdleApplicationLetsSparkleRestartImmediately() {
        let gate = UpdateRestartGate()
        XCTAssertFalse(gate.postpone { XCTFail("Sparkle should handle this restart") })
    }

    func testCanceledUpdateDoesNotRestartWhenDictationFinishes() {
        let gate = UpdateRestartGate()
        gate.isBusy = true
        XCTAssertTrue(gate.postpone { XCTFail("Canceled update must not restart") })
        gate.cancel()
        gate.isBusy = false
    }
}
