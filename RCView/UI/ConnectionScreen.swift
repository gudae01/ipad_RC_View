import SwiftUI

@MainActor
struct ConnectionScreen: View {
    @ObservedObject var model: ViewerModel
    @Binding var showHelp: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("연결 정보").font(.title2.weight(.semibold))
                        Text("iPad가 확인한 외부 장치와 수신 상태입니다.")
                            .font(.subheadline).foregroundStyle(RCTheme.secondary)
                    }
                    Spacer()
                    Button { model.refresh() } label: {
                        Label("다시 검색", systemImage: "arrow.clockwise")
                    }.buttonStyle(RCButtonStyle())
                }
                if model.isDemo {
                    Label("데모 데이터입니다. 실제 캡처카드의 측정값이 아닙니다.", systemImage: "info.circle")
                        .font(.subheadline).foregroundStyle(RCTheme.accent)
                }
                RCCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("외부 영상 장치").font(.headline)
                        if model.snapshot.devices.isEmpty {
                            Label("외부 영상 장치를 찾지 못했습니다.", systemImage: "cable.connector")
                                .foregroundStyle(RCTheme.secondary)
                        }
                        ForEach(model.snapshot.devices, id: \.id) { device in
                            Button { model.selectDevice(device.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "video").foregroundStyle(RCTheme.accent)
                                    Text(device.name).multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: model.snapshot.selectedDeviceID == device.id
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(model.snapshot.selectedDeviceID == device.id
                                                         ? RCTheme.accent : RCTheme.border)
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(device.name)\(model.snapshot.selectedDeviceID == device.id ? ", 선택됨" : ", 선택")")
                        }
                        Text("내장 카메라로 자동 전환하지 않습니다.")
                            .font(.caption).foregroundStyle(RCTheme.secondary)
                    }
                }
                RCCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("입력 형식").font(.headline)
                        detailRow("활성 형식", value: model.snapshot.activeFormatDescription ?? "아직 활성화되지 않음")
                        if !model.snapshot.formats.isEmpty {
                            Picker("지원 형식", selection: Binding(
                                get: { model.snapshot.selectedFormatID ?? "" },
                                set: { model.selectFormat($0) })) {
                                    if model.snapshot.selectedFormatID == nil {
                                        Text("형식 선택").tag("")
                                    }
                                    ForEach(model.snapshot.formats, id: \.id) { format in
                                        Text(format.title).tag(format.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(minHeight: 44)
                                .disabled(![CapturePhase.receiving, .waiting, .stalled].contains(model.snapshot.phase))
                        }
                        Text("장치가 보고한 지원 형식만 표시합니다. 이 값은 캡처카드의 USB 출력 형식이며, HDMI 원본의 세부 정보를 보장하지 않습니다.")
                            .font(.caption).foregroundStyle(RCTheme.secondary)
                    }
                }
                RCCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("수신 상태").font(.headline)
                        detailRow("상태", value: model.snapshot.phase.title)
                        detailRow("카메라 권한", value: model.snapshot.permissionDescription)
                        detailRow("관측된 수신 FPS", value: model.snapshot.observedFPS.map { String(format: "%.1f FPS", $0) } ?? "측정 전")
                        Text(model.snapshot.detail).font(.subheadline).foregroundStyle(RCTheme.secondary)
                        Divider()
                        Text("프레임 수신은 조종기 영상이 정상이라는 뜻이 아닙니다. 캡처카드의 검은 화면 또는 ‘No Signal’ 화면도 프레임으로 수신될 수 있습니다.")
                            .font(.caption).foregroundStyle(RCTheme.secondary)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { actions }
                            VStack(alignment: .leading, spacing: 12) { actions }
                        }
                    }
                }
                Text("전체 지연은 조종기 출력부터 iPad 표시까지 별도로 실측해야 합니다. 수신 FPS는 지연 측정값이 아닙니다.")
                    .font(.caption).foregroundStyle(RCTheme.secondary)
            }
            .padding(1)
        }
    }

    @ViewBuilder private var actions: some View {
        if model.snapshot.phase == .denied {
            Button("카메라 권한 설정", action: openSystemSettings).buttonStyle(RCButtonStyle(prominent: true))
        } else {
            Button("다시 연결") { model.reconnect() }.buttonStyle(RCButtonStyle(prominent: true))
                .disabled(model.snapshot.selectedDeviceID == nil)
        }
        Button("연결 방법") { showHelp = true }.buttonStyle(RCButtonStyle())
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title).foregroundStyle(RCTheme.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

struct EventHistorySheet: View {
    let events: [ConnectionEvent]
    let isDemo: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if events.isEmpty {
                    ContentUnavailableView("아직 연결 내역이 없습니다", systemImage: "bell",
                                           description: Text("연결·해제·오류 내역이 여기에 표시됩니다."))
                } else {
                    List {
                        if isDemo { Text("데모 연결 내역").foregroundStyle(RCTheme.accent) }
                        ForEach(events, id: \.id) { event in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(event.message).font(.body)
                                Text(event.date, style: .time).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("연결 알림")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
