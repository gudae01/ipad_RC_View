import Foundation

enum FrameHealth: Equatable {
    case waiting, receiving, stalled
}

/// Measures arrival of buffers, never the image contents. A static or black
/// picture is still live input when buffers continue to arrive.
struct FrameHealthMonitor {
    let timeout: TimeInterval
    private var startedAt: TimeInterval = 0
    private var lastFrameAt: TimeInterval?
    private var windowStartedAt: TimeInterval = 0
    private var windowFrames = 0

    init(timeout: TimeInterval = 2.5) {
        self.timeout = max(timeout, 0.001)
    }

    mutating func reset(at time: TimeInterval) {
        startedAt = time
        lastFrameAt = nil
        windowStartedAt = time
        windowFrames = 0
    }

    mutating func recordFrame(at time: TimeInterval) {
        if lastFrameAt == nil {
            // The first arrival establishes the sample-window boundary; it
            // must not add a whole extra frame to the first FPS estimate.
            windowStartedAt = time
            windowFrames = 0
        } else {
            windowFrames += 1
        }
        lastFrameAt = time
    }

    func state(at time: TimeInterval) -> FrameHealth {
        if let lastFrameAt {
            return time - lastFrameAt >= timeout ? .stalled : .receiving
        }
        return time - startedAt >= timeout ? .stalled : .waiting
    }

    mutating func sampleFPS(at time: TimeInterval) -> Double? {
        let elapsed = time - windowStartedAt
        guard elapsed >= 1 else { return nil }
        let fps = Double(windowFrames) / elapsed
        windowStartedAt = time
        windowFrames = 0
        return fps
    }
}
