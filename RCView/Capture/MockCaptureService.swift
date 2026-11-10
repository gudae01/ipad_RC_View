import AVFoundation
import Foundation

/// An explicit simulator-only UI fixture. It does not manufacture FPS,
/// resolution or hardware names and never opens an iPad camera.
final class MockCaptureService: CaptureService {
    let session = AVCaptureSession()
    let isDemo = true
    var updateHandler: ((CaptureSnapshot) -> Void)?

    private var snapshot = CaptureSnapshot()
    private var autoPreview = true
    private var active = true
    private var begun = false
    private var previewRequested = true

    func begin(autoPreview: Bool) {
        guard !begun else { return }
        begun = true
        self.autoPreview = autoPreview
        previewRequested = autoPreview
        snapshot.permissionDescription = "데모 — 실제 권한 요청 없음"
        snapshot.devices = [ExternalDevice(id: "demo", name: "데모 장치 · 실제 연결 아님")]
        update()
    }

    func setAutoPreview(_ enabled: Bool) {
        autoPreview = enabled
        if enabled { previewRequested = true }
        if begun { update() }
    }

    func refresh() { if begun { update() } }
    func reconnect() { previewRequested = true; update() }

    func selectDevice(_ id: String) {
        guard id == "demo" else { return }
        previewRequested = true
        update()
    }

    func selectFormat(_ id: String) {}

    func setActive(_ active: Bool) {
        self.active = active
        if begun { update() }
    }

    private func update() {
        if !active {
            snapshot.phase = .paused
            snapshot.detail = "데모 미리보기가 일시 정지되었습니다."
        } else if previewRequested {
            snapshot.phase = .receiving
            snapshot.detail = "데모 · 실제 영상 입력이 아닌 UI 미리보기 예시입니다."
            snapshot.selectedDeviceID = "demo"
            snapshot.selectedDeviceName = "데모 장치 · 실제 연결 아님"
        } else {
            snapshot.phase = .unavailable
            snapshot.detail = "데모 · 연결 화면에서 데모 장치를 선택하세요."
        }
        if snapshot.events.first?.message != snapshot.detail {
            snapshot.events.insert(ConnectionEvent(message: snapshot.detail), at: 0)
            if snapshot.events.count > 40 { snapshot.events.removeLast() }
        }
        // Deliberately nil: simulation cannot report a real format or observed FPS.
        snapshot.observedFPS = nil
        snapshot.activeFormatDescription = nil
        updateHandler?(snapshot)
    }
}
