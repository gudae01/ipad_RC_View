import AVFoundation
import Combine
import Foundation

@MainActor
final class ViewerModel: ObservableObject {
    let session: AVCaptureSession
    let isDemo: Bool
    @Published private(set) var snapshot = CaptureSnapshot()
    @Published var autoPreview: Bool {
        didSet {
            UserDefaults.standard.set(autoPreview, forKey: "autoPreview")
            service.setAutoPreview(autoPreview)
        }
    }

    private let service: CaptureService

    convenience init() {
        #if targetEnvironment(simulator)
        self.init(service: MockCaptureService())
        #else
        self.init(service: ExternalCaptureService())
        #endif
    }

    init(service: CaptureService) {
        self.service = service
        session = service.session
        isDemo = service.isDemo
        autoPreview = UserDefaults.standard.object(forKey: "autoPreview") as? Bool ?? true
        service.updateHandler = { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                self?.snapshot = value
            }
        }
    }

    func begin() { service.begin(autoPreview: autoPreview) }
    func refresh() { service.refresh() }
    func reconnect() { service.reconnect() }
    func selectDevice(_ id: String) { service.selectDevice(id) }
    func selectFormat(_ id: String) { service.selectFormat(id) }
    func setActive(_ active: Bool) { service.setActive(active) }
}
