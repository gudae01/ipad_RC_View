import XCTest
@testable import RCView

final class VideoFormatPolicyTests: XCTestCase {
    func testDimensionsAllowUHDAndRejectOversizedOrInvalidModes() {
        XCTAssertTrue(VideoFormatPolicy.supportsDimensions(width: 3_840, height: 2_160))
        XCTAssertTrue(VideoFormatPolicy.supportsDimensions(width: 1_280, height: 720))
        XCTAssertFalse(VideoFormatPolicy.supportsDimensions(width: 4_096, height: 2_160))
        XCTAssertFalse(VideoFormatPolicy.supportsDimensions(width: 3_840, height: 2_161))
        XCTAssertFalse(VideoFormatPolicy.supportsDimensions(width: 0, height: 1_080))
        XCTAssertFalse(VideoFormatPolicy.supportsDimensions(width: 1_920, height: -1))
        XCTAssertFalse(VideoFormatPolicy.supportsDimensions(width: Int.max, height: Int.max))
    }

    func testSupportedRateAllowsDurationRoundingButRejectsOutOfRangeValues() {
        for rate in [0.5, 29.97, 59.94, 60, 60.000001] {
            XCTAssertTrue(VideoFormatPolicy.isSupported(mode("supported", fps: rate)))
        }
        for rate in [0, -1, 60.000002, 120, Double.infinity, -Double.infinity, Double.nan] {
            XCTAssertFalse(VideoFormatPolicy.isSupported(mode("unsupported", fps: rate)))
        }
        XCTAssertFalse(VideoFormatPolicy.isSupported(mode("too-wide", width: 4_096, height: 2_160)))
    }

    func testCandidatesStayInsideReportedRangeAndIncludeValidEndpoints() {
        XCTAssertEqual(VideoFormatPolicy.candidateFrameRates(min: 27, max: 55),
                       [27, 29.97, 30, 50, 55])
        XCTAssertEqual(VideoFormatPolicy.candidateFrameRates(min: 30, max: 30), [30])
        XCTAssertEqual(VideoFormatPolicy.candidateFrameRates(min: 59.95, max: 60), [59.95, 60])
    }

    func testWideRateRangeIncludesSixtyWithoutOfferingHigherRates() {
        XCTAssertEqual(VideoFormatPolicy.candidateFrameRates(min: 1, max: 120),
                       [1, 24, 25, 29.97, 30, 50, 59.94, 60])
        XCTAssertEqual(VideoFormatPolicy.candidateFrameRates(min: 120, max: 120), [])
        XCTAssertEqual(VideoFormatPolicy.candidateFrameRates(min: 61, max: 120), [])
    }

    func testInvalidRateRangesProduceNoCandidates() {
        for range in [(0.0, 60.0), (-1.0, 60.0), (60.0, 30.0),
                      (Double.nan, 60.0), (1.0, Double.infinity), (Double.infinity, Double.infinity)] {
            XCTAssertEqual(VideoFormatPolicy.candidateFrameRates(min: range.0, max: range.1), [])
        }
    }

    func testPrefersUHDAtSixtyWhenDeviceReportsIt() {
        let uhd = mode("uhd60", width: 3_840, height: 2_160, fps: 60)
        let formats = [mode("fhd60"), mode("uhd30", width: 3_840, height: 2_160, fps: 30), uhd]
        XCTAssertEqual(VideoFormatPolicy.preferredFormat(in: formats), uhd)
    }

    func testPrefersFullHDAtSixtyOverUHDAtThirty() {
        let fhd = mode("fhd60")
        let formats = [mode("uhd30", width: 3_840, height: 2_160, fps: 30), fhd]
        XCTAssertEqual(VideoFormatPolicy.preferredFormat(in: formats), fhd)
    }

    func testFractionalSixtyTierPrefersResolutionAndPreservesActualRate() {
        let uhd = mode("uhd5994", width: 3_840, height: 2_160, fps: 59.94)
        XCTAssertEqual(VideoFormatPolicy.preferredFormat(in: [mode("fhd60"), uhd]), uhd)
        let exactNTSC = mode("uhdNTSC", width: 3_840, height: 2_160, fps: 60_000.0 / 1_001)
        XCTAssertEqual(VideoFormatPolicy.preferredFormat(in: [mode("fhd60"), exactNTSC]), exactNTSC)
    }

    func testEqualResolutionPrefersActualRateThenStableIdentifier() {
        XCTAssertEqual(VideoFormatPolicy.preferredFormat(in: [mode("fractional", fps: 59.94), mode("sixty")])?.id,
                       "sixty")
        let formats = [mode("z-mode"), mode("a-mode")]
        XCTAssertEqual(VideoFormatPolicy.preferredFormat(in: formats)?.id, "a-mode")
        XCTAssertEqual(VideoFormatPolicy.preferredFormat(in: Array(formats.reversed()))?.id, "a-mode")
    }

    func testPreferenceSkipsUnsupportedModesAndReturnsNilWithoutAValidChoice() {
        let unsupported = [mode("8k", width: 7_680, height: 4_320),
                           mode("120fps", fps: 120), mode("nan", fps: .nan),
                           mode("invalid-dimensions", width: -1)]
        XCTAssertNil(VideoFormatPolicy.preferredFormat(in: []))
        XCTAssertNil(VideoFormatPolicy.preferredFormat(in: unsupported))
        let fallback = mode("only-supported", width: 1_280, height: 720, fps: 30)
        XCTAssertEqual(VideoFormatPolicy.preferredFormat(in: unsupported + [fallback]), fallback)
    }

    private func mode(_ id: String, width: Int = 1_920, height: Int = 1_080,
                      fps: Double = 60) -> VideoFormatOption {
        VideoFormatOption(id: id, title: id, width: width, height: height, fps: fps)
    }
}
