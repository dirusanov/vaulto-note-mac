import XCTest
@testable import VaultoNote

final class OnboardingTests: XCTestCase {
    func testPracticeWaitsThroughDownloadAndModelPreparation() {
        XCTAssertEqual(status(.notLoaded), .waiting)
        XCTAssertEqual(status(.notLoaded, downloading: true), .downloading)
        XCTAssertEqual(status(.loading), .preparing)
        XCTAssertEqual(status(.ready), .ready)
    }

    func testActiveDownloadDoesNotInvitePracticeWithPreviouslyLoadedModel() {
        XCTAssertEqual(status(.ready, downloading: true), .downloading)
    }

    func testDownloadFailureIsShownInsteadOfWaitingForever() {
        XCTAssertEqual(status(.notLoaded, error: "No internet connection"), .failed("No internet connection"))
        XCTAssertEqual(status(.notLoaded, downloading: true, error: "Previous error"), .downloading)
    }

    func testLoadingFailureIsShownAndRecoveredModelCanBeUsed() {
        XCTAssertEqual(status(.failed("Invalid model")), .failed("Invalid model"))
        XCTAssertEqual(status(.loading, error: "Previous download failed"), .preparing)
        XCTAssertEqual(status(.ready, error: "Previous download failed"), .ready)
    }

    private func status(_ state: AppController.ModelState, downloading: Bool = false,
                        error: String? = nil) -> PracticeModelStatus {
        PracticeModelStatus(modelState: state, downloading: downloading, downloadError: error)
    }
}
