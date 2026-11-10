import XCTest
@testable import RCView

final class CaptureRecoveryPolicyTests: XCTestCase {
    func testRecoveryStopsAfterThreeRetriesEvenWhenDeviceRemainsMissing() {
        var policy = CaptureRecoveryPolicy()
        XCTAssertFalse(policy.takeRetry(at: 100, needsRecovery: true))
        policy.begin(at: 0)
        XCTAssertFalse(policy.takeRetry(at: 0.9, needsRecovery: true))
        XCTAssertTrue(policy.takeRetry(at: 1, needsRecovery: true))
        XCTAssertFalse(policy.takeRetry(at: 2.9, needsRecovery: true))
        XCTAssertTrue(policy.takeRetry(at: 3, needsRecovery: true))
        XCTAssertFalse(policy.takeRetry(at: 6.9, needsRecovery: true))
        XCTAssertTrue(policy.takeRetry(at: 7, needsRecovery: true))
        XCTAssertFalse(policy.takeRetry(at: 100, needsRecovery: true))
        XCTAssertEqual(policy.attempts, 3)
        XCTAssertTrue(policy.cycleStarted)
        XCTAssertFalse(policy.hasPendingRetry)
    }

    func testSlowFirstFrameWaitPreservesRetryBudgetUntilCaptureActuallyStalls() {
        var health = FrameHealthMonitor(timeout: 12)
        var policy = CaptureRecoveryPolicy()
        health.reset(at: 0)
        policy.begin(at: 0)
        for time in [1.0, 3, 7, 11.9] {
            XCTAssertFalse(policy.takeRetry(at: time, needsRecovery: health.state(at: time) == .stalled))
        }
        XCTAssertEqual(policy.attempts, 0)
        XCTAssertTrue(policy.hasPendingRetry)
        XCTAssertTrue(policy.takeRetry(at: 12, needsRecovery: health.state(at: 12) == .stalled))
        XCTAssertEqual(policy.attempts, 1)
    }

    func testLateWatchdogCallbacksCannotIssueRetriesBackToBack() {
        var policy = CaptureRecoveryPolicy()
        policy.begin(at: 0)
        XCTAssertTrue(policy.takeRetry(at: 100, needsRecovery: true))
        XCTAssertFalse(policy.takeRetry(at: 100, needsRecovery: true))
        XCTAssertFalse(policy.takeRetry(at: 101.9, needsRecovery: true))
        XCTAssertTrue(policy.takeRetry(at: 102, needsRecovery: true))
        XCTAssertFalse(policy.takeRetry(at: 102, needsRecovery: true))
        XCTAssertTrue(policy.takeRetry(at: 106, needsRecovery: true))
    }

    func testRepeatedErrorNotificationsDoNotPostponeOrRearmTheCycle() {
        var policy = CaptureRecoveryPolicy()
        policy.beginIfNeeded(at: 0)
        policy.beginIfNeeded(at: 0.8)
        XCTAssertTrue(policy.takeRetry(at: 1, needsRecovery: true))
        policy.beginIfNeeded(at: 2)
        XCTAssertTrue(policy.takeRetry(at: 3, needsRecovery: true))
        XCTAssertTrue(policy.takeRetry(at: 7, needsRecovery: true))
        policy.beginIfNeeded(at: 100)
        XCTAssertFalse(policy.takeRetry(at: 101, needsRecovery: true))
        XCTAssertEqual(policy.attempts, 3)
        XCTAssertFalse(policy.hasPendingRetry)
    }

    func testFrameArrivalOrInactivityCancelsPendingRecovery() {
        var policy = CaptureRecoveryPolicy()
        policy.begin(at: 0)
        XCTAssertTrue(policy.takeRetry(at: 1, needsRecovery: true))
        policy.cancel()
        XCTAssertFalse(policy.cycleStarted)
        XCTAssertFalse(policy.hasPendingRetry)
        XCTAssertEqual(policy.attempts, 0)
        XCTAssertFalse(policy.takeRetry(at: 100, needsRecovery: true))
    }

    func testExplicitNewForegroundCycleRestoresACompletedRetryBudget() {
        var policy = CaptureRecoveryPolicy()
        policy.begin(at: 0)
        for time in [1.0, 3, 7] {
            XCTAssertTrue(policy.takeRetry(at: time, needsRecovery: true))
        }
        policy.begin(at: 100)
        XCTAssertEqual(policy.attempts, 0)
        XCTAssertTrue(policy.hasPendingRetry)
        XCTAssertFalse(policy.takeRetry(at: 100.9, needsRecovery: true))
        XCTAssertTrue(policy.takeRetry(at: 101, needsRecovery: true))
        XCTAssertEqual(policy.attempts, 1)
    }
}
