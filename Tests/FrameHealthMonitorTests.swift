import XCTest
@testable import RCView

final class FrameHealthMonitorTests: XCTestCase {
    func testMissingInitialFramesDoesNotImmediatelyReportDisconnection() {
        var monitor = FrameHealthMonitor(timeout: 2.5)
        monitor.reset(at: 10)
        XCTAssertEqual(monitor.state(at: 12.4), .waiting)
        XCTAssertEqual(monitor.state(at: 12.6), .stalled)
    }

    func testActualFrameArrivalRecoversFromStallRegardlessOfImageContent() {
        var monitor = FrameHealthMonitor(timeout: 2.5)
        monitor.reset(at: 0)
        XCTAssertEqual(monitor.state(at: 3), .stalled)
        monitor.recordFrame(at: 3.1)
        XCTAssertEqual(monitor.state(at: 3.2), .receiving)
        XCTAssertEqual(monitor.state(at: 5.7), .stalled)
        monitor.recordFrame(at: 5.8)
        XCTAssertEqual(monitor.state(at: 5.9), .receiving)
    }

    func testFPSUsesElapsedTimeAndDoesNotSampleTooEarly() {
        var monitor = FrameHealthMonitor()
        monitor.reset(at: 0)
        monitor.recordFrame(at: 0.1)
        monitor.recordFrame(at: 0.2)
        XCTAssertNil(monitor.sampleFPS(at: 0.5))
        monitor.recordFrame(at: 0.8)
        XCTAssertNil(monitor.sampleFPS(at: 1))
        XCTAssertEqual(monitor.sampleFPS(at: 1.1) ?? -1, 2, accuracy: 0.0001)
        XCTAssertEqual(monitor.sampleFPS(at: 2.1), 0)
    }

    func testFirstFrameIsMeasurementBaselineNotAnExtraFPSCount() {
        var monitor = FrameHealthMonitor()
        monitor.reset(at: 0)
        monitor.recordFrame(at: 4)
        XCTAssertNil(monitor.sampleFPS(at: 4.5))
        XCTAssertEqual(monitor.sampleFPS(at: 5), 0)
    }

    func testSlowInputRemainsLiveWithinConfiguredArrivalTimeout() {
        var monitor = FrameHealthMonitor(timeout: 12)
        monitor.reset(at: 0)
        monitor.recordFrame(at: 0)
        XCTAssertEqual(monitor.state(at: 3.9), .receiving)
        monitor.recordFrame(at: 4)
        XCTAssertEqual(monitor.state(at: 15.9), .receiving)
        XCTAssertEqual(monitor.state(at: 16), .stalled)
    }

    func testReconnectClearsOldFrameTimestampAndFPSWindow() {
        var monitor = FrameHealthMonitor()
        monitor.reset(at: 0)
        monitor.recordFrame(at: 1)
        monitor.reset(at: 20)
        XCTAssertEqual(monitor.state(at: 20.1), .waiting)
        XCTAssertNil(monitor.sampleFPS(at: 20.5))
        XCTAssertEqual(monitor.sampleFPS(at: 21), 0)
    }
}
