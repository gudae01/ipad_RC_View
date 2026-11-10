import SwiftUI

@MainActor
struct SettingsScreen: View {
    @ObservedObject var model: ViewerModel
    @Binding var autoFullscreen: Bool
    @Binding var preventSleep: Bool
    @Binding var fitMode: String
    @Binding var rotation: Int
    @Binding var showHelp: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("설정").font(.title2.weight(.semibold))
                Text("영상 보기에 필요한 설정만, 이 iPad에 저장합니다.")
                    .font(.subheadline).foregroundStyle(RCTheme.secondary)
                RCCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("자동 동작").font(.headline)
                        Toggle("연결 시 자동 미리보기", isOn: $model.autoPreview).frame(minHeight: 44)
                        Text("장치가 하나일 때 자동으로 시작합니다. 여러 장치가 있으면 직접 선택합니다.")
                            .font(.caption).foregroundStyle(RCTheme.secondary)
                        Divider()
                        Toggle("자동 전체 화면 진입", isOn: $autoFullscreen).frame(minHeight: 44)
                        Text("영상 프레임 수신을 시작하면 전체 화면으로 전환합니다.")
                            .font(.caption).foregroundStyle(RCTheme.secondary)
                        Divider()
                        Toggle("영상 표시 중 화면 꺼짐 방지", isOn: $preventSleep).frame(minHeight: 44)
                        Text("뷰어가 보이고 영상 프레임을 수신할 때만 적용됩니다.")
                            .font(.caption).foregroundStyle(RCTheme.secondary)
                    }
                }
                RCCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("영상 표시").font(.headline)
                        Picker("기본 영상 맞춤", selection: $fitMode) {
                            Text("원본 비율 유지").tag("fit")
                            Text("화면 채우기").tag("fill")
                        }.pickerStyle(.segmented)
                        Text("‘화면 채우기’ 또는 확대 상태에서는 영상 가장자리가 잘릴 수 있습니다.")
                            .font(.caption).foregroundStyle(RCTheme.secondary)
                        Divider()
                        Picker("표시 회전", selection: $rotation) {
                            Text("0°").tag(0)
                            Text("90°").tag(1)
                            Text("180°").tag(2)
                            Text("270°").tag(3)
                        }.frame(minHeight: 44)
                        Text("회전과 확대는 표시 방식만 바꿉니다. 조종기나 드론을 제어하지 않습니다. 좌우 반전은 적용하지 않습니다.")
                            .font(.caption).foregroundStyle(RCTheme.secondary)
                    }
                }
                RCCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Button { showHelp = true } label: {
                            HStack {
                                Label("연결 도움말", systemImage: "questionmark.circle")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }.frame(minHeight: 44)
                        }.buttonStyle(.plain)
                        Divider()
                        HStack {
                            Text("앱 버전")
                            Spacer()
                            Text(version).foregroundStyle(RCTheme.secondary)
                        }
                        Text("회원가입 없이 로컬에서 사용합니다. 영상·오디오를 녹화하거나 서버로 전송하지 않습니다.")
                            .font(.caption).foregroundStyle(RCTheme.secondary)
                    }
                }
            }.padding(1)
        }
    }

    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}

struct ConnectionHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("연결 → 영상 확인 → 전체 화면", systemImage: "display")
                        .font(.title3.weight(.semibold)).foregroundStyle(RCTheme.accent)
                    helpStep("1", title: "조종기의 실제 영상 출력을 먼저 확인하세요",
                             text: "RC 2의 USB-C 영상 출력 지원은 이 앱이 보장하지 않습니다. 현재 조종기·펌웨어·어댑터 조합에서 외부 모니터로 영상이 출력되는지 먼저 확인하세요.")
                    helpStep("2", title: "출력 어댑터와 입력 캡처카드를 구분하세요",
                             text: "영상 출력이 확인된 조종기 → USB-C→HDMI 출력 어댑터 → HDMI 입력·USB 출력 UVC 캡처카드 → iPad 순서입니다. 일반 USB-C→HDMI 출력 어댑터만으로 iPad에 HDMI 영상을 입력할 수 없습니다.")
                    helpStep("3", title: "iPad에 연결하고 카메라 접근을 허용하세요",
                             text: "USB-C가 있는 iPad와 iPadOS 17 이상을 사용하세요. 캡처카드가 인식되면 실제 장치 이름이 표시됩니다. 여러 장치가 연결되어 있으면 ‘연결’에서 선택하세요. 인식되지 않으면 데이터 케이블과 전원 공급을 확인하세요.")
                    helpStep("4", title: "실제 조종기 화면인지 확인하세요",
                             text: "‘프레임 수신 중’이어도 캡처카드의 검은 화면이나 ‘No Signal’ 안내일 수 있습니다. 조종기의 영상 출력과 HDMI 연결을 확인하세요. 앱은 출력 신호가 없는 문제를 해결할 수 없습니다.")
                    helpStep("5", title: "전체 화면에서 편하게 보세요",
                             text: "전체 화면에서는 터치하면 조작부가 나타나고 약 3초 후 숨겨집니다. 핀치로 확대하고 ‘초기화’로 되돌릴 수 있습니다. 회전·확대·터치는 드론 제어와 연결되지 않습니다.")
                    Text("캡처카드 호환성, 장시간 안정성, 발열 및 조종기부터 iPad까지의 전체 지연은 실제 장치로 확인해야 합니다.")
                        .font(.footnote).foregroundStyle(RCTheme.secondary)
                }.padding(24)
            }
            .background(RCTheme.background)
            .navigationTitle("연결 방법")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
    }

    private func helpStep(_ number: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number).font(.headline).foregroundStyle(RCTheme.accent)
                .frame(width: 32, height: 32)
                .background(RCTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(text).font(.body).foregroundStyle(RCTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
