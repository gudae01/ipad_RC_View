import SwiftUI
import UIKit

enum ViewerTab: String, CaseIterable {
    case viewer = "뷰어", connection = "연결", settings = "설정"
    var symbol: String {
        switch self {
        case .viewer: return "play.rectangle"
        case .connection: return "cable.connector"
        case .settings: return "slider.horizontal.3"
        }
    }
}

@MainActor
struct ViewerScreen: View {
    @StateObject private var model = ViewerModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @AppStorage("autoFullscreen") private var autoFullscreen = false
    @AppStorage("preventSleep") private var preventSleep = true
    @AppStorage("displayRotation") private var rotation = 0
    @State private var tab = ViewerTab.viewer
    @State private var fullscreen = false
    @State private var controlsVisible = true
    @State private var showHelp = false
    @State private var showEvents = false
    @State private var zoom: CGFloat = 1
    @State private var gestureStartZoom: CGFloat?
    @State private var hideControlsTask: Task<Void, Never>?

    private var receiving: Bool { model.snapshot.phase == .receiving }
    private var sourceSize: CGSize {
        if let width = model.snapshot.presentationWidth, let height = model.snapshot.presentationHeight,
           width.isFinite, height.isFinite, width > 0, height > 0 {
            return CGSize(width: CGFloat(width), height: CGFloat(height))
        }
        if let format = model.snapshot.formats.first(where: { $0.id == model.snapshot.selectedFormatID }) {
            return CGSize(width: CGFloat(format.width), height: CGFloat(format.height))
        }
        return CGSize(width: 16, height: 9)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: fullscreen ? 0 : 16) {
                if !fullscreen { header(compact: geometry.size.width < 650) }
                if fullscreen || tab == .viewer {
                    viewerContent(compact: geometry.size.width < 650)
                } else if tab == .connection {
                    ConnectionScreen(model: model, showHelp: $showHelp)
                } else {
                    SettingsScreen(model: model, autoFullscreen: $autoFullscreen,
                                   preventSleep: $preventSleep,
                                   rotation: $rotation, showHelp: $showHelp)
                }
                if !fullscreen { navigation }
            }
            .padding(fullscreen ? 0 : (geometry.size.width < 650 ? 16 : 24))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(fullscreen ? .black : RCTheme.background)
        }
        .ignoresSafeArea(.container, edges: fullscreen ? .all : [])
        .foregroundStyle(RCTheme.text)
        .tint(RCTheme.accent)
        .statusBarHidden(fullscreen)
        .persistentSystemOverlays(fullscreen ? .hidden : .automatic)
        .sheet(isPresented: $showHelp) { ConnectionHelpSheet() }
        .sheet(isPresented: $showEvents) { EventHistorySheet(events: model.snapshot.events, isDemo: model.isDemo) }
        .task {
            model.setActive(scenePhase == .active)
            model.begin()
        }
        .onChange(of: scenePhase) { _, phase in
            model.setActive(phase == .active)
            updateIdleTimer()
            if phase != .active { hideControlsTask?.cancel(); controlsVisible = true }
        }
        .onChange(of: model.snapshot.phase) { old, new in
            if new == .receiving, old != .receiving, autoFullscreen, scenePhase == .active {
                fullscreen = true
                tab = .viewer
                revealControls()
            } else if new != .receiving {
                hideControlsTask?.cancel()
                controlsVisible = true
            }
            updateIdleTimer()
        }
        .onChange(of: fullscreen) { _, active in
            if active {
                zoom = 1
                gestureStartZoom = nil
                revealControls()
            } else { hideControlsTask?.cancel(); controlsVisible = true }
            updateIdleTimer()
        }
        .onChange(of: tab) { _, _ in updateIdleTimer() }
        .onChange(of: preventSleep) { _, _ in updateIdleTimer() }
        .onChange(of: rotation) { _, _ in zoom = 1; gestureStartZoom = nil }
        .onChange(of: model.snapshot.selectedDeviceID) { _, _ in zoom = 1; gestureStartZoom = nil }
        .onChange(of: model.snapshot.selectedFormatID) { _, _ in zoom = 1; gestureStartZoom = nil }
        .onChange(of: voiceOverEnabled) { _, _ in revealControls() }
        .onDisappear {
            hideControlsTask?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
            model.setActive(false)
        }
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "display")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(RCTheme.accent)
                .accessibilityHidden(true)
            Text("RC View").font(.system(size: compact ? 22 : 26, weight: .semibold))
            if model.isDemo {
                Text("데모").font(.caption.weight(.semibold))
                    .foregroundStyle(RCTheme.accent).padding(6)
                    .background(RCTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            Spacer(minLength: 0)
            if !compact { StatusLabel(phase: model.snapshot.phase) }
            RCIconButton(title: "연결 알림 내역", symbol: "bell") { showEvents = true }
            RCIconButton(title: "개인 설정 열기", symbol: "person.crop.circle") { tab = .settings }
        }
        .frame(minHeight: 44)
    }

    private func viewerContent(compact: Bool) -> some View {
        VStack(spacing: 0) {
            videoSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .clipShape(RoundedRectangle(cornerRadius: fullscreen ? 0 : RCTheme.radius))
                .overlay {
                    if !fullscreen {
                        RoundedRectangle(cornerRadius: RCTheme.radius).stroke(RCTheme.border, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
            if !fullscreen {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        if compact { Image(systemName: model.snapshot.phase.symbol) }
                        Text(metadata).lineLimit(2)
                        Spacer(minLength: 0)
                        if zoom > 1.01 { Text(String(format: "%.1f×", zoom)).monospacedDigit() }
                    }
                    .font(.system(size: 13)).foregroundStyle(RCTheme.secondary)
                    normalControls(compact: compact)
                }
                .padding(.top, 12)
            }
        }
    }

    private var videoSurface: some View {
        ZStack {
            (receiving || fullscreen ? Color.black : RCTheme.card)
            if model.isDemo {
                if receiving {
                    DemoVideo(sourceSize: sourceSize, quarterTurns: rotation, zoom: zoom)
                }
            } else {
                CapturePreview(session: model.session, sourceSize: sourceSize,
                               quarterTurns: rotation, zoom: zoom)
                    .opacity(receiving ? 1 : 0)
                    .accessibilityHidden(!receiving)
            }
            // Never present a frozen preview as live after frames stop arriving.
            if !receiving {
                (fullscreen ? Color.black : RCTheme.card)
                emptyState
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard fullscreen else { return }
            if controlsVisible && receiving && !voiceOverEnabled {
                hideControlsTask?.cancel()
                withAnimation(.easeOut(duration: 0.15)) { controlsVisible = false }
            } else { revealControls() }
        }
        .gesture(MagnifyGesture()
            .onChanged { value in
                guard receiving else { return }
                if gestureStartZoom == nil { gestureStartZoom = zoom }
                zoom = min(4, max(1, (gestureStartZoom ?? 1) * value.magnification))
                if fullscreen { revealControls() }
            }
            .onEnded { _ in gestureStartZoom = nil; if fullscreen { revealControls() } })
        .accessibilityAction(named: "확대 초기화") { resetZoom() }
        .accessibilityAction(named: fullscreen ? "전체 화면 종료" : "전체 화면") { fullscreen.toggle() }
        // Controls sit outside the video gesture region: a button tap must not
        // also toggle the visibility of the surrounding video controls.
        .overlay {
            if fullscreen && controlsVisible { fullscreenControls }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: model.snapshot.phase.symbol)
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(fullscreen ? Color.white.opacity(0.8) : RCTheme.accent)
                .accessibilityHidden(true)
            Text(emptyTitle).font(.system(size: 24, weight: .semibold)).multilineTextAlignment(.center)
            Text(model.snapshot.detail)
                .font(.system(size: 15)).multilineTextAlignment(.center)
                .foregroundStyle(fullscreen ? Color.white.opacity(0.72) : RCTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.snapshot.phase == .checkingPermission || model.snapshot.phase == .reconnecting {
                ProgressView().tint(fullscreen ? .white : RCTheme.accent)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { emptyActions }
                    VStack(spacing: 12) { emptyActions }
                }
            }
        }
        .foregroundStyle(fullscreen ? .white : RCTheme.text)
        .padding(fullscreen ? 64 : 24)
        .frame(maxWidth: 580)
    }

    @ViewBuilder private var emptyActions: some View {
        if model.snapshot.phase == .denied {
            Button("설정에서 권한 허용", action: openSystemSettings).buttonStyle(RCButtonStyle(prominent: true))
        } else if model.snapshot.devices.count == 1 && model.snapshot.selectedDeviceID == nil {
            Button("미리보기 시작") {
                if let device = model.snapshot.devices.first { model.selectDevice(device.id) }
            }.buttonStyle(RCButtonStyle(prominent: true))
        } else if model.snapshot.devices.count > 1 && model.snapshot.selectedDeviceID == nil {
            Button("장치 선택") { fullscreen = false; tab = .connection }.buttonStyle(RCButtonStyle(prominent: true))
        } else {
            Button(model.snapshot.selectedDeviceID == nil ? "장치 다시 찾기" : "다시 연결") {
                if model.snapshot.selectedDeviceID == nil { model.refresh() } else { model.reconnect() }
            }.buttonStyle(RCButtonStyle(prominent: true))
        }
        Button("연결 방법") { showHelp = true }.buttonStyle(RCButtonStyle(dark: fullscreen))
    }

    private var emptyTitle: String {
        switch model.snapshot.phase {
        case .unavailable: return model.snapshot.devices.isEmpty ? "캡처카드를 연결해 주세요" : "외부 장치를 선택해 주세요"
        case .denied: return "카메라 접근을 허용해 주세요"
        case .disconnected: return "연결이 끊어졌습니다"
        case .stalled: return "영상 프레임이 도착하지 않습니다"
        default: return model.snapshot.phase.title
        }
    }

    private var metadata: String {
        var values: [String] = []
        if model.isDemo { values.append("데모 · 실제 장치 아님") }
        if let device = model.snapshot.selectedDeviceName { values.append(device) }
        if let format = model.snapshot.activeFormatDescription { values.append(format) }
        if let fps = model.snapshot.observedFPS, receiving {
            values.append(String(format: "수신 %.1f FPS", fps))
        }
        if values.isEmpty { values.append(model.snapshot.phase.title) }
        return values.joined(separator: "  ·  ")
    }

    private func normalControls(compact: Bool) -> some View {
        HStack(spacing: 8) {
            if compact {
                RCIconButton(title: "확대 초기화", symbol: "arrow.counterclockwise", action: resetZoom)
                    .disabled(!receiving)
                RCIconButton(title: "시계 방향 90도 회전", symbol: "rotate.right", action: rotate)
                    .disabled(!receiving)
            } else {
                Button(action: resetZoom) { Label("확대 초기화", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(RCButtonStyle()).disabled(!receiving)
                Button(action: rotate) { Label("회전", systemImage: "rotate.right") }
                    .buttonStyle(RCButtonStyle()).disabled(!receiving)
            }
            Spacer(minLength: 0)
            Button { fullscreen = true } label: {
                Label("전체 화면", systemImage: "arrow.up.left.and.arrow.down.right")
            }.buttonStyle(RCButtonStyle(prominent: true))
        }
    }

    private var fullscreenControls: some View {
        VStack {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Button { fullscreen = false } label: {
                        Label("전체 화면 종료", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(RCButtonStyle(dark: true))
                    .keyboardShortcut(.escape, modifiers: [])
                    Spacer(minLength: 12)
                    StatusLabel(phase: model.snapshot.phase, dark: true)
                }
                HStack {
                    RCIconButton(title: "전체 화면 종료", symbol: "arrow.down.right.and.arrow.up.left", dark: true) {
                        fullscreen = false
                    }
                    Spacer(minLength: 8)
                    StatusLabel(phase: model.snapshot.phase, dark: true, compact: true)
                }
            }
            Spacer()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Button(action: resetZoom) { Label("초기화", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(RCButtonStyle(dark: true)).disabled(!receiving)
                    Button(action: rotate) { Label("회전", systemImage: "rotate.right") }
                        .buttonStyle(RCButtonStyle(dark: true)).disabled(!receiving)
                    Spacer(minLength: 8)
                }
                HStack(spacing: 12) {
                    RCIconButton(title: "확대 초기화", symbol: "arrow.counterclockwise", dark: true, action: resetZoom)
                        .disabled(!receiving)
                    RCIconButton(title: "시계 방향 90도 회전", symbol: "rotate.right", dark: true, action: rotate)
                        .disabled(!receiving)
                    Spacer(minLength: 8)
                }
            }
        }
        .padding(24)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .transition(.opacity)
    }

    private var navigation: some View {
        HStack(spacing: 8) {
            ForEach(ViewerTab.allCases, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.system(size: 14, weight: tab == item ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(tab == item ? RCTheme.accent : RCTheme.secondary)
                        .background(tab == item ? RCTheme.accent.opacity(0.08) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(6)
        .background(.white, in: RoundedRectangle(cornerRadius: RCTheme.radius))
        .overlay(RoundedRectangle(cornerRadius: RCTheme.radius).stroke(RCTheme.border, lineWidth: 1))
    }

    private func resetZoom() { zoom = 1; gestureStartZoom = nil; if fullscreen { revealControls() } }
    private func rotate() { rotation = (rotation + 1) % 4; if fullscreen { revealControls() } }

    private func revealControls() {
        hideControlsTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { controlsVisible = true }
        guard fullscreen, receiving, !voiceOverEnabled, scenePhase == .active else { return }
        hideControlsTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard !Task.isCancelled, fullscreen, receiving else { return }
            withAnimation(.easeOut(duration: 0.2)) { controlsVisible = false }
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = preventSleep && receiving
            && scenePhase == .active && (fullscreen || tab == .viewer)
    }
}

@MainActor
func openSystemSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
}
