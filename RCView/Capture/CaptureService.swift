import AVFoundation

/// Implementations own their session and serialize every session mutation.
/// The update handler is installed once before begin() and receives value snapshots.
protocol CaptureService: AnyObject {
    var session: AVCaptureSession { get }
    var isDemo: Bool { get }
    var updateHandler: ((CaptureSnapshot) -> Void)? { get set }
    func begin(autoPreview: Bool)
    func setAutoPreview(_ enabled: Bool)
    func refresh()
    func reconnect()
    func selectDevice(_ id: String)
    func selectFormat(_ id: String)
    func setActive(_ active: Bool)
}
