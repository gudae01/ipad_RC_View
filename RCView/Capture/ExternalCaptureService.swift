import AVFoundation
import CoreMedia
import Foundation

/// All device discovery, session mutation, delegate callbacks and frame health
/// bookkeeping run on one serial queue. UI receives immutable snapshots only.
final class ExternalCaptureService: NSObject, CaptureService, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let isDemo = false
    var updateHandler: ((CaptureSnapshot) -> Void)?

    private let queue = DispatchQueue(label: "app.rcview.capture", qos: .userInitiated)
    private var snapshot = CaptureSnapshot()
    private var observers: [NSObjectProtocol] = []
    private var watchdog: DispatchSourceTimer?
    private var input: AVCaptureDeviceInput?
    private var output: AVCaptureVideoDataOutput?
    private var nativeFormats: [String: NativeFormat] = [:]
    private var desiredDeviceID: String?
    private var desiredFormat: VideoFormatOption?
    private var frameHealth = FrameHealthMonitor()
    private var begun = false
    private var active = true
    private var autoPreview = true
    private var wantsToRun = true
    private var interrupted = false
    private var permissionRequestInFlight = false
    private var recovery = CaptureRecoveryPolicy()

    private struct NativeFormat {
        let option: VideoFormatOption
        let format: AVCaptureDevice.Format
        let frameDuration: CMTime
    }

    private enum SetupError: LocalizedError {
        case inputUnavailable, outputUnavailable, noFormats, invalidFormat

        var errorDescription: String? {
            switch self {
            case .inputUnavailable: return "이 외부 장치를 영상 세션에 연결할 수 없습니다."
            case .outputUnavailable: return "영상 프레임을 관측할 출력을 만들 수 없습니다."
            case .noFormats: return "장치에서 3840 × 2160 이하·60fps 이하의 지원 형식을 찾지 못했습니다."
            case .invalidFormat: return "선택한 형식이 현재 장치에서 더 이상 지원되지 않습니다."
            }
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        watchdog?.setEventHandler {}
        watchdog?.cancel()
        let captureSession = session
        queue.async {
            if captureSession.isRunning { captureSession.stopRunning() }
        }
    }

    func begin(autoPreview: Bool) {
        queue.async { [weak self] in
            guard let self, !self.begun else { return }
            self.begun = true
            self.autoPreview = autoPreview
            self.wantsToRun = autoPreview
            self.installObservers()
            self.installWatchdog()
            if self.wantsToRun { self.recovery.begin(at: ProcessInfo.processInfo.systemUptime) }
            self.authorizeAndDiscover()
        }
    }

    func setAutoPreview(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.autoPreview = enabled
            if !enabled && self.input == nil {
                self.wantsToRun = false
                self.recovery.cancel()
            }
            if enabled && self.input == nil {
                self.wantsToRun = true
                if self.begun {
                    self.recovery.begin(at: ProcessInfo.processInfo.systemUptime)
                    self.authorizeAndDiscover()
                }
            }
        }
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self, self.begun else { return }
            self.authorizeAndDiscover()
        }
    }

    func reconnect() {
        queue.async { [weak self] in
            guard let self, self.begun else { return }
            // Clear a failed manual choice and negotiate the preferred supported format again.
            if self.snapshot.phase == .failed { self.desiredFormat = nil }
            self.wantsToRun = true
            self.recovery.begin(at: ProcessInfo.processInfo.systemUptime)
            self.authorizeAndDiscover(forceReconfigure: true)
        }
    }

    func selectDevice(_ id: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.desiredDeviceID = id
            self.desiredFormat = nil
            self.wantsToRun = true
            self.recovery.begin(at: ProcessInfo.processInfo.systemUptime)
            self.authorizeAndDiscover(forceReconfigure: true)
        }
    }

    func selectFormat(_ id: String) {
        queue.async { [weak self] in
            guard let self, self.active,
                  let choice = self.snapshot.formats.first(where: { $0.id == id }),
                  let deviceID = self.snapshot.selectedDeviceID else { return }
            // A failed high-bandwidth format may have removed the session input.
            // Rediscover the external device so a lower supported mode can recover it.
            guard let device = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.external], mediaType: .video, position: .unspecified
            ).devices.first(where: { $0.uniqueID == deviceID && $0.isConnected }) else { return }
            self.desiredFormat = choice
            self.wantsToRun = true
            self.recovery.begin(at: ProcessInfo.processInfo.systemUptime)
            self.configure(device: device, selectedFormatID: id)
        }
    }

    func setActive(_ active: Bool) {
        queue.async { [weak self] in
            guard let self, self.active != active else { return }
            self.active = active
            guard self.begun else { return }
            if active {
                // USB devices may appear later than the foreground transition.
                // Preserve the previous device, format and explicit start intent.
                if self.wantsToRun { self.recovery.begin(at: ProcessInfo.processInfo.systemUptime) }
                self.authorizeAndDiscover(forceReconfigure: true)
            } else {
                self.recovery.cancel()
                self.stopAndRemoveGraph()
                self.snapshot.observedFPS = nil
                self.transition(.paused, "화면을 켜고 앱으로 돌아오면 연결된 외부 장치의 영상을 자동으로 다시 표시합니다.")
            }
        }
    }

    private func authorizeAndDiscover(forceReconfigure: Bool = false) {
        guard active else {
            transition(.paused, "앱으로 돌아오면 외부 장치를 다시 확인합니다.")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            snapshot.permissionDescription = "허용"
            discover(forceReconfigure: forceReconfigure)
        case .notDetermined:
            snapshot.permissionDescription = "확인 중"
            transition(.checkingPermission, "외부 영상 장치를 표시하려면 카메라 접근을 허용해 주세요.")
            guard !permissionRequestInFlight else { return }
            permissionRequestInFlight = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                guard let self else { return }
                self.queue.async { [weak self] in
                    self?.permissionRequestInFlight = false
                    self?.authorizeAndDiscover(forceReconfigure: true)
                }
            }
        case .denied, .restricted:
            recovery.cancel()
            stopAndRemoveGraph()
            clearSelectionSnapshot()
            snapshot.devices = []
            snapshot.permissionDescription = AVCaptureDevice.authorizationStatus(for: .video) == .restricted
                ? "시스템에서 제한됨" : "거부됨"
            transition(.denied, "설정에서 RC View의 카메라 접근을 허용해 주세요. 기기 제한이 설정된 경우 제한 설정도 확인해 주세요.")
        @unknown default:
            recovery.cancel()
            stopAndRemoveGraph()
            snapshot.permissionDescription = "알 수 없음"
            transition(.failed, "카메라 권한을 확인하지 못했습니다. 앱을 다시 열어 주세요.")
        }
    }

    private func discover(forceReconfigure: Bool = false) {
        // Never use userPreferredCamera/systemPreferredCamera or a built-in fallback.
        // A reattached physical device is represented by a NEW device instance.
        let discovered = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external], mediaType: .video, position: .unspecified
        ).devices.filter { $0.isConnected }
        snapshot.devices = discovered.map { ExternalDevice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        guard !discovered.isEmpty else {
            let wasConnected = input != nil || desiredDeviceID != nil
            stopAndRemoveGraph()
            clearSelectionSnapshot()
            // A temporary USB disappearance during wake must not erase a
            // manually started stream when automatic preview is disabled.
            if wantsToRun && recovery.hasPendingRetry {
                transition(.reconnecting, "연결된 외부 영상 장치를 다시 찾고 있습니다. 잠시 기다려 주세요.")
                return
            }
            transition(wasConnected ? .disconnected : .unavailable,
                       wasConnected
                        ? "외부 영상 장치가 분리되었습니다. 캡처카드를 다시 연결해 주세요."
                        : "외부 영상 장치를 찾지 못했습니다. UVC 캡처카드와 USB-C 연결을 확인해 주세요.")
            return
        }

        let chosen: AVCaptureDevice?
        if let desiredDeviceID {
            // Preserve an explicit/previous device choice; never silently jump
            // to another capture card when the previous card disappears.
            chosen = discovered.first { $0.uniqueID == desiredDeviceID }
        } else if discovered.count == 1 && wantsToRun {
            chosen = discovered.first
        } else {
            chosen = nil
        }

        guard let device = chosen else {
            stopAndRemoveGraph()
            clearSelectionSnapshot()
            if desiredDeviceID == nil { recovery.cancel() }
            if desiredDeviceID != nil && wantsToRun && recovery.hasPendingRetry {
                transition(.reconnecting, "사용하던 외부 영상 장치를 다시 찾고 있습니다. 다른 장치로 전환하지 않습니다.")
                return
            }
            let message = desiredDeviceID != nil
                ? "사용하던 장치가 없습니다. 다시 연결하거나 장치 목록에서 사용할 장치를 선택해 주세요."
                : discovered.count > 1
                    ? "외부 영상 장치가 여러 개입니다. 연결 화면에서 사용할 장치를 선택해 주세요."
                    : "자동 미리보기가 꺼져 있습니다. 연결 화면에서 장치를 선택해 미리보기를 시작하세요."
            transition(desiredDeviceID == nil ? .unavailable : .disconnected, message)
            return
        }

        guard wantsToRun else {
            recovery.cancel()
            stopAndRemoveGraph()
            clearSelectionSnapshot()
            transition(.unavailable, "외부 장치가 감지되었습니다. 자동 미리보기가 꺼져 있으므로 연결 화면에서 장치를 선택해 주세요.")
            return
        }
        desiredDeviceID = device.uniqueID
        if !forceReconfigure, let input, input.device.isConnected,
           input.device.uniqueID == device.uniqueID, session.isRunning {
            publish()
            return
        }
        configure(device: device)
    }

    private func configure(device: AVCaptureDevice, selectedFormatID: String? = nil) {
        guard active, device.isConnected else { return }
        transition(.reconnecting, "외부 영상 장치를 준비하고 있습니다.")
        stopAndRemoveGraph()
        clearSelectionSnapshot()
        snapshot.selectedDeviceID = device.uniqueID
        snapshot.selectedDeviceName = device.localizedName
        interrupted = false

        do {
            let formats = enumerateFormats(device)
            snapshot.formats = formats.map(\.option)
            guard !formats.isEmpty else { throw SetupError.noFormats }
            nativeFormats = Dictionary(uniqueKeysWithValues: formats.map { ($0.option.id, $0) })
            let choice: NativeFormat
            if let selectedFormatID {
                guard let selected = nativeFormats[selectedFormatID] else { throw SetupError.invalidFormat }
                choice = selected
            } else if let previous = desiredFormat,
                      let matching = formats.first(where: {
                          $0.option.title == previous.title
                      }) {
                choice = matching
            } else {
                guard let preferred = VideoFormatPolicy.preferredFormat(in: formats.map(\.option)),
                      let selected = nativeFormats[preferred.id] else { throw SetupError.noFormats }
                choice = selected
            }

            let newInput = try AVCaptureDeviceInput(device: device)
            let newOutput = AVCaptureVideoDataOutput()
            newOutput.alwaysDiscardsLateVideoFrames = true
            // nil asks AVFoundation for its default uncompressed format rather
            // than forcing a BGRA conversion. We never read/copy pixel data.
            newOutput.videoSettings = nil
            newOutput.setSampleBufferDelegate(self, queue: queue)

            session.beginConfiguration()
            do {
                if session.isMultitaskingCameraAccessSupported {
                    session.isMultitaskingCameraAccessEnabled = true
                }
                // Input-priority prevents a session preset from overriding the
                // explicit hardware format selected below.
                if session.canSetSessionPreset(.inputPriority) { session.sessionPreset = .inputPriority }
                guard session.canAddInput(newInput) else { throw SetupError.inputUnavailable }
                session.addInput(newInput)
                guard session.canAddOutput(newOutput) else { throw SetupError.outputUnavailable }
                session.addOutput(newOutput)
                try device.lockForConfiguration()
                device.activeFormat = choice.format
                device.activeVideoMinFrameDuration = choice.frameDuration
                device.activeVideoMaxFrameDuration = choice.frameDuration
                device.unlockForConfiguration()
                if let connection = newOutput.connection(with: .video) {
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                    // Do not rotate data-output buffers: that incurs processing.
                }
                session.commitConfiguration()
            } catch {
                session.inputs.forEach(session.removeInput)
                session.outputs.forEach(session.removeOutput)
                session.commitConfiguration()
                throw error
            }

            input = newInput
            output = newOutput
            desiredFormat = choice.option
            snapshot.selectedDeviceID = device.uniqueID
            snapshot.selectedDeviceName = device.localizedName
            snapshot.formats = formats.map(\.option)
            snapshot.selectedFormatID = choice.option.id
            let actualDimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            let presentation = CMVideoFormatDescriptionGetPresentationDimensions(
                device.activeFormat.formatDescription, usePixelAspectRatio: true, useCleanAperture: true
            )
            snapshot.presentationWidth = Double(presentation.width)
            snapshot.presentationHeight = Double(presentation.height)
            let duration = CMTimeGetSeconds(device.activeVideoMinFrameDuration)
            let configuredFPS = duration.isFinite && duration > 0 ? 1 / duration : choice.option.fps
            snapshot.activeFormatDescription = "\(actualDimensions.width) × \(actualDimensions.height) · \(Self.fpsText(configuredFPS)) fps"
            // A legitimately slow mode must not be called stalled between frames.
            frameHealth = FrameHealthMonitor(timeout: max(2.5, 3 / configuredFPS))
            transition(.waiting, "캡처카드는 연결되었지만 아직 영상 프레임이 도착하지 않았습니다.")
            session.startRunning()
            // Starting a USB device can itself block during wake. Sample
            // callbacks share this queue, so start the arrival timeout only
            // after startRunning returns and before any first frame is handled.
            frameHealth.reset(at: ProcessInfo.processInfo.systemUptime)
            if !session.isRunning && !session.isInterrupted {
                transition(.failed, "영상 세션을 시작하지 못했습니다. 연결과 전원을 확인한 뒤 재연결해 주세요.")
            }
        } catch {
            stopAndRemoveGraph()
            snapshot.selectedFormatID = nil
            snapshot.activeFormatDescription = nil
            snapshot.presentationWidth = nil
            snapshot.presentationHeight = nil
            // Keep the device's advertised options available after a setup failure.
            transition(.failed, "\(error.localizedDescription) 연결 화면에서 더 낮은 지원 형식을 선택하거나 캡처카드를 다시 연결해 주세요.")
        }
    }

    private func enumerateFormats(_ device: AVCaptureDevice) -> [NativeFormat] {
        var choices: [NativeFormat] = []
        for (index, format) in device.formats.enumerated() {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard VideoFormatPolicy.supportsDimensions(width: Int(dimensions.width), height: Int(dimensions.height)) else { continue }
            let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            let codec = String(bytes: [24, 16, 8, 0].map { UInt8((subtype >> $0) & 0xff) }, encoding: .ascii) ?? "video"
            var seenDurations = Set<String>()
            for range in format.videoSupportedFrameRateRanges {
                guard range.minFrameRate.isFinite, range.maxFrameRate.isFinite,
                      range.minFrameRate > 0, range.maxFrameRate >= range.minFrameRate else { continue }
                // Only offer endpoints and common rates actually contained in
                // a reported range. No guessed resolution/rate is shown.
                let rates = VideoFormatPolicy.candidateFrameRates(min: range.minFrameRate, max: range.maxFrameRate)
                for rate in rates {
                    let duration: CMTime
                    if abs(rate - range.maxFrameRate) < 0.000001 {
                        duration = range.minFrameDuration
                    } else if abs(rate - range.minFrameRate) < 0.000001 {
                        duration = range.maxFrameDuration
                    } else {
                        let proposed = CMTime(seconds: 1 / rate, preferredTimescale: 1_000_000_000)
                        // Clamp nanosecond rounding to the device's exact bounds.
                        duration = CMTimeMaximum(range.minFrameDuration, CMTimeMinimum(range.maxFrameDuration, proposed))
                    }
                    let seconds = CMTimeGetSeconds(duration)
                    guard seconds.isFinite, seconds > 0 else { continue }
                    let actualFPS = 1 / seconds
                    let rateKey = String(format: "%.6f", actualFPS)
                    guard seenDurations.insert(rateKey).inserted else { continue }
                    let option = VideoFormatOption(
                        id: "\(index):\(rateKey)",
                        title: "\(dimensions.width) × \(dimensions.height) · \(Self.fpsText(actualFPS)) fps · \(codec)",
                        width: Int(dimensions.width), height: Int(dimensions.height), fps: actualFPS
                    )
                    guard VideoFormatPolicy.isSupported(option) else { continue }
                    choices.append(NativeFormat(option: option, format: format, frameDuration: duration))
                }
            }
        }
        return choices.sorted {
            if $0.option.width != $1.option.width { return $0.option.width > $1.option.width }
            if $0.option.height != $1.option.height { return $0.option.height > $1.option.height }
            if abs($0.option.fps - $1.option.fps) > 0.001 { return $0.option.fps > $1.option.fps }
            return $0.option.id < $1.option.id
        }
    }

    private static func fpsText(_ fps: Double) -> String {
        abs(fps.rounded() - fps) < 0.01 ? String(format: "%.0f", fps) : String(format: "%.2f", fps)
    }

    private func stopAndRemoveGraph() {
        if session.isRunning { session.stopRunning() }
        output?.setSampleBufferDelegate(nil, queue: nil)
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.commitConfiguration()
        input = nil
        output = nil
        nativeFormats = [:]
        frameHealth.reset(at: ProcessInfo.processInfo.systemUptime)
        snapshot.observedFPS = nil
    }

    private func clearSelectionSnapshot() {
        snapshot.selectedDeviceID = nil
        snapshot.selectedDeviceName = nil
        snapshot.formats = []
        snapshot.selectedFormatID = nil
        snapshot.activeFormatDescription = nil
        snapshot.presentationWidth = nil
        snapshot.presentationHeight = nil
        snapshot.observedFPS = nil
    }

    private func installObservers() {
        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] note in
                guard let device = note.object as? AVCaptureDevice, device.deviceType == .external else { return }
                let connected = name == AVCaptureDevice.wasConnectedNotification
                let deviceName = device.localizedName
                let deviceID = device.uniqueID
                self?.queue.async { [weak self] in
                    guard let self else { return }
                    self.addEvent("\(deviceName) — \(connected ? "장치 연결" : "장치 연결 해제")")
                    if self.active {
                        if connected && self.wantsToRun,
                           self.desiredDeviceID == nil || self.desiredDeviceID == deviceID {
                            self.recovery.beginIfNeeded(at: ProcessInfo.processInfo.systemUptime)
                        }
                        self.authorizeAndDiscover()
                    } else { self.publish() }
                }
            })
        }
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, self.active, self.session.isInterrupted else { return }
                self.interrupted = true
                self.snapshot.observedFPS = nil
                if self.wantsToRun { self.recovery.beginIfNeeded(at: ProcessInfo.processInfo.systemUptime) }
                self.transition(.stalled, "시스템이 영상 세션을 일시 중단했습니다. 다른 카메라 사용 앱을 닫아 주세요. 창 모드에서 계속 중단되면 iPad의 앱 창을 전체 화면으로 확장해 주세요.")
            }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, !self.session.isInterrupted else { return }
                self.interrupted = false
                if self.active && self.wantsToRun {
                    // The OS may resume delivery itself. The watchdog only
                    // reconfigures if the normal frame-arrival timeout expires.
                    self.recovery.beginIfNeeded(at: ProcessInfo.processInfo.systemUptime)
                }
            }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            let message = error?.localizedDescription ?? "원인을 확인할 수 없는 오류"
            self?.queue.async { [weak self] in
                guard let self, self.active else { return }
                // An error notification can be queued by a graph that has
                // already been replaced. Do not tear down a healthy new graph;
                // let the watchdog inspect current session/frame state first.
                self.addEvent("영상 세션 알림: \(message)")
                if self.wantsToRun { self.recovery.beginIfNeeded(at: ProcessInfo.processInfo.systemUptime) }
                if !self.session.isRunning && !self.session.isInterrupted {
                    self.snapshot.observedFPS = nil
                    self.transition(.failed, "영상 세션 오류: \(message). 연결된 외부 장치의 영상을 다시 확인합니다.")
                } else {
                    self.publish()
                }
            }
        })
    }

    private func installWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self, self.active, self.wantsToRun else { return }
            let now = ProcessInfo.processInfo.systemUptime
            var needsRecovery = self.input == nil
            if self.input != nil {
                // Ignore stale interruption notifications from a pre-lock graph.
                self.interrupted = self.session.isInterrupted
                if self.interrupted {
                    self.snapshot.observedFPS = nil
                    self.transition(.stalled, "시스템이 영상 세션을 일시 중단했습니다. 다른 카메라 사용 앱을 닫아 주세요. 창 모드에서 계속 중단되면 iPad의 앱 창을 전체 화면으로 확장해 주세요.")
                    self.recovery.beginIfNeeded(at: now)
                    // Do not fight an OS-owned interruption with repeated starts.
                    // Keep the budget for when the session becomes available.
                    needsRecovery = false
                } else if !self.session.isRunning {
                    self.snapshot.observedFPS = nil
                    self.transition(.stalled, "영상 세션이 멈췄습니다. 연결된 외부 장치의 영상을 다시 확인합니다.")
                    self.recovery.beginIfNeeded(at: now)
                    needsRecovery = true
                } else if self.frameHealth.state(at: now) == .stalled {
                    self.snapshot.observedFPS = nil
                    self.transition(.stalled, "캡처카드는 연결되었지만 영상 프레임이 도착하지 않습니다. 조종기 출력과 HDMI 연결을 확인해 주세요.")
                    self.recovery.beginIfNeeded(at: now)
                    needsRecovery = true
                } else {
                    // Respect each format's initial-frame/low-FPS timeout;
                    // a scheduled retry must not tear down a healthy wait.
                    needsRecovery = false
                    if let fps = self.frameHealth.sampleFPS(at: now), self.snapshot.phase == .receiving {
                        self.snapshot.observedFPS = fps
                        self.publish()
                    }
                }
            }
            let authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            if self.recovery.takeRetry(at: now, needsRecovery: needsRecovery && authorized && !self.session.isInterrupted) {
                self.addEvent("외부 영상 연결 자동 복구 \(self.recovery.attempts)/3")
                self.authorizeAndDiscover(forceReconfigure: true)
            }
        }
        watchdog = timer
        timer.resume()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard output === self.output, active, !interrupted, session.isRunning,
              CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if snapshot.phase != .receiving {
            frameHealth.reset(at: now)
        }
        recovery.cancel()
        frameHealth.recordFrame(at: now)
        if snapshot.phase != .receiving {
            transition(.receiving, "영상 프레임을 수신하고 있습니다. 조종기 영상의 정상 여부는 화면에서 확인해 주세요.")
        }
        // No image-buffer access, copy, processing, encoding or frame queue.
    }

    private func transition(_ phase: CapturePhase, _ detail: String) {
        let changed = snapshot.phase != phase || snapshot.detail != detail
        snapshot.phase = phase
        snapshot.detail = detail
        if changed { addEvent("\(phase.title) · \(detail)") }
        publish()
    }

    private func addEvent(_ message: String) {
        snapshot.events.insert(ConnectionEvent(message: message), at: 0)
        if snapshot.events.count > 80 { snapshot.events.removeLast(snapshot.events.count - 80) }
    }

    private func publish() { updateHandler?(snapshot) }
}
