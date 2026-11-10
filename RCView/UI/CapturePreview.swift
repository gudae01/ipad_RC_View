import AVFoundation
import SwiftUI
import UIKit

/// Display-only transforms: no frame copies, processing, encoding or device control.
struct CapturePreview: UIViewRepresentable {
    let session: AVCaptureSession
    let sourceSize: CGSize
    let quarterTurns: Int
    let zoom: CGFloat

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ view: PreviewHostView, context: Context) {
        let sessionChanged = view.previewLayer.session !== session
        if sessionChanged { view.previewLayer.session = session }
        // FPS/status updates do not change the geometry of the live video.
        let geometryChanged = view.sourceSize != sourceSize
            || view.quarterTurns != quarterTurns || view.zoom != zoom
        view.sourceSize = sourceSize
        view.quarterTurns = quarterTurns
        view.zoom = zoom
        view.configureConnection()
        if sessionChanged || geometryChanged { view.setNeedsLayout() }
    }

    static func dismantleUIView(_ view: PreviewHostView, coordinator: ()) {
        view.previewLayer.session = nil
    }
}

final class PreviewHostView: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    var sourceSize = CGSize(width: 16, height: 9)
    var quarterTurns = 0
    var zoom: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityLabel = "외부 입력 영상"
        previewLayer.videoGravity = .resizeAspect
        layer.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let source = CGSize(width: max(sourceSize.width, 1), height: max(sourceSize.height, 1))
        let turns = ((quarterTurns % 4) + 4) % 4
        let rotated = turns.isMultiple(of: 2) ? source : CGSize(width: source.height, height: source.width)
        let x = bounds.width / rotated.width
        let y = bounds.height / rotated.height
        let factor = min(x, y)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        configureConnection()
        previewLayer.bounds = CGRect(origin: .zero,
                                     size: CGSize(width: source.width * factor, height: source.height * factor))
        previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        previewLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(turns) * .pi / 2)
            .scaledBy(x: zoom, y: zoom))
        CATransaction.commit()
    }

    func configureConnection() {
        // A session rebuild can replace this connection without changing geometry.
        if let connection = previewLayer.connection {
            if connection.automaticallyAdjustsVideoMirroring {
                connection.automaticallyAdjustsVideoMirroring = false
            }
            if connection.isVideoMirroringSupported && connection.isVideoMirrored {
                connection.isVideoMirrored = false
            }
            if connection.videoRotationAngle != 0 && connection.isVideoRotationAngleSupported(0) {
                connection.videoRotationAngle = 0
            }
        }
    }
}

/// Simulator-only illustrative landscape. It is never selected for a real disconnected iPad.
struct DemoVideo: View {
    let sourceSize: CGSize
    let quarterTurns: Int
    let zoom: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let source = CGSize(width: max(sourceSize.width, 1), height: max(sourceSize.height, 1))
            let turns = ((quarterTurns % 4) + 4) % 4
            let rotated = turns.isMultiple(of: 2) ? source : CGSize(width: source.height, height: source.width)
            let factor = min(geometry.size.width / rotated.width, geometry.size.height / rotated.height)
            landscape
                .frame(width: source.width * factor, height: source.height * factor)
                .rotationEffect(.degrees(Double(turns) * 90))
                .scaleEffect(zoom)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .clipped()
        .accessibilityLabel("데모 풍경. 실제 입력 영상이 아닙니다.")
    }

    private var landscape: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xB7CFD7)))
            let mountainColors: [UInt32] = [0x8DA6A6, 0x708D86, 0x4C7066]
            for index in 0..<3 {
                let base = size.height * (0.44 + CGFloat(index) * 0.15)
                var ridge = Path()
                ridge.move(to: CGPoint(x: 0, y: base))
                for step in 0...12 {
                    let x = size.width * CGFloat(step) / 12
                    let wave = CGFloat(sin(Double(step) * 1.4 + Double(index))) * size.height * 0.10
                    ridge.addLine(to: CGPoint(x: x, y: base + wave))
                }
                ridge.addLine(to: CGPoint(x: size.width, y: size.height))
                ridge.addLine(to: CGPoint(x: 0, y: size.height))
                ridge.closeSubpath()
                context.fill(ridge, with: .color(Color(hex: mountainColors[index])))
            }
            var river = Path()
            river.move(to: CGPoint(x: size.width * 0.65, y: size.height * 0.56))
            river.addCurve(to: CGPoint(x: size.width * 0.43, y: size.height),
                           control1: CGPoint(x: size.width * 0.3, y: size.height * 0.7),
                           control2: CGPoint(x: size.width * 0.85, y: size.height * 0.85))
            context.stroke(river, with: .color(Color(hex: 0xB8CED0)), style: StrokeStyle(lineWidth: size.width * 0.045))
        }
        .overlay(alignment: .topLeading) {
            Text("데모 · 미리보기 예시")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(.white)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .padding(16)
        }
    }
}
