import Foundation

/// A finite recovery cycle after the caller's immediate connection attempt.
/// The service decides whether capture has actually stalled; a healthy first-
/// frame wait (including slow input formats) must not consume retries.
struct CaptureRecoveryPolicy {
    private static let retryDelays: [TimeInterval] = [1, 2, 4]
    private var nextRetryAt: TimeInterval?
    private(set) var cycleStarted = false
    private(set) var attempts = 0

    var hasPendingRetry: Bool { nextRetryAt != nil }

    init() {}

    mutating func begin(at time: TimeInterval) {
        cycleStarted = true
        attempts = 0
        nextRetryAt = time + Self.retryDelays[0]
    }

    mutating func beginIfNeeded(at time: TimeInterval) {
        // Keep an exhausted cycle latched until real recovery, explicit retry,
        // or a new foreground transition. Repeated errors cannot rearm it.
        guard !cycleStarted else { return }
        begin(at: time)
    }

    mutating func cancel() {
        cycleStarted = false
        attempts = 0
        nextRetryAt = nil
    }

    mutating func takeRetry(at time: TimeInterval, needsRecovery: Bool) -> Bool {
        guard needsRecovery, cycleStarted,
              let deadline = nextRetryAt, time >= deadline else { return false }
        attempts += 1
        // Schedule from this actual attempt, not the old deadline, so a late
        // watchdog callback cannot burst through the remaining retry budget.
        nextRetryAt = attempts < Self.retryDelays.count
            ? time + Self.retryDelays[attempts] : nil
        return true
    }
}
