import Foundation

enum CapturePhase: String, Equatable, Sendable {
    case checkingPermission, denied, unavailable, waiting, receiving
    case stalled, disconnected, reconnecting, paused, failed

    var title: String {
        switch self {
        case .checkingPermission: return "카메라 권한 확인 중"
        case .denied: return "카메라 접근 권한 필요"
        case .unavailable: return "연결 대기"
        case .waiting: return "프레임 대기"
        case .receiving: return "프레임 수신 중"
        case .stalled: return "영상 입력 중단"
        case .disconnected: return "연결이 끊어졌습니다"
        case .reconnecting: return "재연결 중"
        case .paused: return "미리보기 일시 정지"
        case .failed: return "영상 세션 오류"
        }
    }
}

struct ExternalDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

struct VideoFormatOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let width: Int
    let height: Int
    let fps: Double
}

struct ConnectionEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let message: String

    init(message: String, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.message = message
    }
}

struct CaptureSnapshot: Equatable, Sendable {
    var phase: CapturePhase = .checkingPermission
    var detail = "외부 영상 장치를 사용하기 위한 카메라 권한을 확인합니다."
    var devices: [ExternalDevice] = []
    var selectedDeviceID: String?
    var selectedDeviceName: String?
    var formats: [VideoFormatOption] = []
    var selectedFormatID: String?
    var activeFormatDescription: String?
    // Presentation dimensions include pixel aspect ratio and clean aperture.
    // These affect display geometry, not the reported encoded input resolution.
    var presentationWidth: Double?
    var presentationHeight: Double?
    var observedFPS: Double?
    var permissionDescription = "확인 중"
    var events: [ConnectionEvent] = []
}
