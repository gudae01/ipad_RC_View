import Foundation

/// Chooses only device-reported modes within the viewer's UHD / 60 fps limits.
/// This policy never creates a resolution or expands a reported frame-rate range.
enum VideoFormatPolicy {
    static let maximumWidth = 3_840
    static let maximumHeight = 2_160
    static let maximumFrameRate = 60.0
    private static let frameRateRoundingTolerance = 0.000001

    static func supportsDimensions(width: Int, height: Int) -> Bool {
        width > 0 && height > 0 && width <= maximumWidth && height <= maximumHeight
    }

    static func isSupported(_ option: VideoFormatOption) -> Bool {
        supportsDimensions(width: option.width, height: option.height)
            && option.fps.isFinite && option.fps > 0
            && option.fps <= maximumFrameRate + frameRateRoundingTolerance
    }

    static func candidateFrameRates(min minimum: Double, max maximum: Double) -> [Double] {
        guard minimum.isFinite, maximum.isFinite,
              minimum > 0, maximum >= minimum else { return [] }
        let candidates = [minimum, maximum, 24, 25, 29.97, 30, 50, 59.94, 60]
        // Do not clamp an unsupported rate into the range. For example, a fixed
        // 120 fps mode cannot supply 60 fps, whereas a 1...120 fps range can.
        return Array(Set(candidates.filter {
            $0 >= minimum && $0 <= maximum && $0 <= maximumFrameRate
        })).sorted()
    }

    static func preferredFormat(in formats: [VideoFormatOption]) -> VideoFormatOption? {
        var preferred: VideoFormatOption?
        for format in formats where isSupported(format) {
            if let current = preferred {
                if isPreferred(format, over: current) { preferred = format }
            } else {
                preferred = format
            }
        }
        return preferred
    }

    private static func isPreferred(_ lhs: VideoFormatOption, over rhs: VideoFormatOption) -> Bool {
        // Treat the standard 59.94 and 60 fps modes as the same smoothness tier.
        // The precise device-supported rate is retained in the chosen option.
        let lhsRate = lhs.fps >= 59.94 ? maximumFrameRate : lhs.fps
        let rhsRate = rhs.fps >= 59.94 ? maximumFrameRate : rhs.fps
        if lhsRate != rhsRate { return lhsRate > rhsRate }
        let lhsPixels = lhs.width * lhs.height
        let rhsPixels = rhs.width * rhs.height
        if lhsPixels != rhsPixels { return lhsPixels > rhsPixels }
        if lhs.fps != rhs.fps { return lhs.fps > rhs.fps }
        return lhs.id < rhs.id
    }
}
