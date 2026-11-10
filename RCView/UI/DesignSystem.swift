import SwiftUI

enum RCTheme {
    static let background = Color(hex: 0xF8F9FA)
    static let card = Color.white
    static let text = Color(hex: 0x1A1A1A)
    static let secondary = Color(hex: 0x667085)
    static let border = Color(hex: 0xE5E7EB)
    static let accent = Color(hex: 0x526D82)
    static let radius: CGFloat = 12
    static let spacing: CGFloat = 16
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}

struct RCCard<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RCTheme.card, in: RoundedRectangle(cornerRadius: RCTheme.radius))
            .overlay(RoundedRectangle(cornerRadius: RCTheme.radius).stroke(RCTheme.border, lineWidth: 1))
    }
}

struct RCButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false
    var dark = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .foregroundStyle(prominent || dark ? .white : RCTheme.text)
            .background(prominent ? RCTheme.accent : (dark ? Color.white.opacity(0.14) : .white),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(dark ? Color.white.opacity(0.22) : (prominent ? .clear : RCTheme.border), lineWidth: 1))
            .opacity(!isEnabled ? 0.4 : (configuration.isPressed ? 0.7 : 1))
    }
}

struct RCIconButton: View {
    let title: String
    let symbol: String
    var dark = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
                .frame(width: 44, height: 44)
                .foregroundStyle(dark ? .white : RCTheme.secondary)
                .background(dark ? Color.black.opacity(0.5) : .clear,
                            in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }
}

struct StatusLabel: View {
    let phase: CapturePhase
    var dark = false
    var compact = false
    var body: some View {
        Label(phase.title, systemImage: phase.symbol)
            .font(compact ? .caption2.weight(.medium) : .caption.weight(.medium))
            .foregroundStyle(dark ? .white : RCTheme.secondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(dark ? Color.black.opacity(0.55) : RCTheme.background, in: Capsule())
            .accessibilityLabel("연결 상태: \(phase.title)")
    }
}

extension CapturePhase {
    var symbol: String {
        switch self {
        case .receiving: return "checkmark.circle"
        case .checkingPermission, .reconnecting: return "arrow.triangle.2.circlepath"
        case .waiting: return "hourglass"
        case .denied: return "camera.badge.ellipsis"
        case .stalled, .failed: return "exclamationmark.triangle"
        case .paused: return "pause.circle"
        case .disconnected: return "cable.connector.slash"
        case .unavailable: return "cable.connector"
        }
    }
}
