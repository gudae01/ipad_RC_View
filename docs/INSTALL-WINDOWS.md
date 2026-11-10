# Windows에서 빌드하고 개인 iPad에 설치하기

## 무료 경로와 한계

```text
Windows 소스 편집 → GitHub Actions macOS 빌드 → RCView-unsigned.ipa 다운로드
→ Windows Sideloadly 서명/설치 → iPad 개발자 모드/신뢰 → RC View 실행
```

Mac 구매, 유료 Apple Developer Program, TestFlight가 필요하지 않습니다. 무료 Apple 계정의 개발용 서명은 **7일** 후 만료됩니다. 만료 전에 갱신해야 하며, 무료 프로파일로 설치 가능한 앱 수는 **3개**입니다. 단순히 IPA를 iPad로 복사해서 실행하는 방식은 아닙니다.

안내 확인일: 2026-11-10. 서비스 정책이나 메뉴는 변경될 수 있습니다.

## 1. 준비물

- Windows PC와 데이터 전송 가능한 USB 케이블.
- USB-C iPad, iPadOS 17 이상. 모델별 실제 UVC 호환성 확인 필요.
- 본인 Apple 계정과 GitHub 무료 계정.
- 코드 편집기(예: VS Code), Git 또는 GitHub Desktop.
- [공식 Sideloadly](https://sideloadly.io/), 이 사이트가 연결하는 **Apple 웹 배포판 iTunes 및 iCloud**. Sideloadly는 Microsoft Store판 대신 웹판을 요구합니다.

Apple 비밀번호와 이중 인증 코드는 **본인 PC의 Sideloadly 인증 화면에서 직접 입력**합니다. 저장소, Actions YAML, 채팅, 앱 소스에는 입력하지 않습니다. 이 프로젝트의 클라우드 빌드에는 Apple 인증서/계정/Secrets가 필요 없습니다.

## 2. GitHub 저장소 만들기

소스를 공개해도 된다면 GitHub에서 `RCView`라는 **Public 저장소**를 생성합니다. 소스 공개를 원하지 않으면 Private을 선택하고 계정의 무료 빌드 한도 안에서 사용합니다.

공개 저장소의 **표준** GitHub macOS 실행기 사용은 무료입니다. 대형 실행기는 사용하지 마세요. Artifact 저장공간은 별도 한도가 있으므로 이 프로젝트는 짧은 보관 기간을 사용합니다. 비용이 없어야 한다면 결제수단을 등록하지 않은 무료 계정을 사용하거나 기존 계정의 사용 중단 예산을 확인하세요. 무료 한도를 넘으면 빌드/업로드가 차단될 수 있습니다.

출처: [GitHub Actions 요금과 무료 사용량](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

GitHub Desktop을 사용하는 경우:

1. 프로젝트 폴더를 로컬 저장소로 추가/생성합니다.
2. 프로젝트 파일을 커밋합니다.
3. `Publish repository`에서 공개 여부를 확인한 뒤 게시합니다.
4. `.github/workflows`가 원격 저장소에 포함되었는지 확인합니다.

명령줄을 사용한다면 프로젝트 루트에서 실행합니다. 아래 URL의 `YOUR_ACCOUNT`는 본인 이름으로 바꿉니다.

```powershell
git init -b main
git add .
git commit -m "Add RC View iPad app"
git remote add origin https://github.com/YOUR_ACCOUNT/RCView.git
git push -u origin main
```

기존 Git 저장소에서는 `git init`과 `remote add`를 반복하지 말고 현재 원격을 확인합니다. 개인 파일이 아닌 이 앱 폴더만 업로드합니다.

## 3. 프로젝트 정합성 확인

Swift 파일 추가/삭제 후에는 아래 명령을 실행하고 변경된 프로젝트도 커밋합니다.

```powershell
py -3 scripts/generate_project.py
py -3 scripts/validate_project.py
```

체크인된 `.xcodeproj`가 있으므로 XcodeGen이나 로컬 Mac은 필요 없습니다. Python 생성기가 Swift 파일과 테스트를 프로젝트에 등록합니다.

## 4. GitHub Actions 빌드

1. GitHub 저장소에서 **Actions**를 엽니다.
2. 비활성 안내가 나타나면 본인의 저장소 워크플로를 활성화합니다.
3. **Build RC View IPA** 워크플로를 선택하고 **Run workflow**를 누릅니다.
4. 실행 로그에서 프로젝트 검사, 테스트, 기기용 빌드, 패키징 성공을 확인합니다.
5. 실행 결과의 **Artifacts**에서 IPA 결과를 내려받습니다.
6. 다운로드한 ZIP을 풀어 `RCView-unsigned.ipa`를 꺼냅니다. `SHA256SUMS.txt`와 다음 명령의 결과를 대조할 수 있습니다. `BUILD-INFO.json`에는 빌드 메타데이터가 들어 있습니다.

```powershell
Get-FileHash -Algorithm SHA256 .\RCView-unsigned.ipa
```

이 파일은 **실제 iPad용 arm64 앱을 담은 미서명 IPA**입니다. Windows의 Sideloadly가 마지막 서명 단계를 수행합니다. 시뮬레이터 빌드 결과는 실제 iPad에 설치할 수 없습니다.

실패한 실행은 IPA가 준비된 것이 아닙니다. 가장 먼저 실패한 단계의 오류를 확인하세요. `Scheme not found`나 누락된 파일 오류는 프로젝트 생성/커밋 상태를, Swift 오류는 해당 소스를 확인합니다. Apple 인증서 오류가 난다면 서명을 끄는 빌드 플래그가 유지되는지 확인합니다. 결제나 유료 개발자 가입으로 해결하려 하지 않아도 됩니다.

## 5. Sideloadly 설치

1. iPad를 USB로 연결하고 잠금을 풉니다.
2. iPad에서 **이 컴퓨터를 신뢰**를 선택합니다.
3. iTunes에서 기기가 보이는지 확인합니다.
4. Sideloadly를 열고 대상 iPad를 선택합니다.
5. `RCView-unsigned.ipa`를 끌어다 놓습니다.
6. 본인 무료 Apple 계정을 입력하고 **Start**를 누릅니다.
7. 필요 시 계정 비밀번호와 이중 인증을 직접 입력합니다.
8. 완료 후 iPad 홈 화면에 RC View가 나타나는지 확인합니다.

앱의 Bundle ID와 설치에 쓰는 Apple 계정은 이후에도 유지하세요. 다른 앱과 충돌하면 최초 설치 전에 고유 Bundle ID로 정하고 계속 같은 값을 사용합니다. 무료 계정에서는 앱 전용 암호가 지원되지 않는 경우가 있으므로 Sideloadly의 현재 인증 안내를 따릅니다.

출처: [Sideloadly](https://sideloadly.io/), [Sideloadly FAQ](https://sideloadly.io/faq).

## 6. iPad 실행 허용

1. **설정 → 일반 → VPN 및 기기 관리 → 개발자 계정 → 신뢰**.
2. **설정 → 개인정보 보호 및 보안 → 개발자 모드 → 켜기**.
3. 재시작 후 개발자 모드를 켜겠다는 확인을 마칩니다.
4. 메뉴가 없으면 앱 설치/실행을 먼저 시도하고 다시 확인합니다.
5. RC View를 실행하고 **카메라 접근 허용**을 선택합니다.

권한을 거부했다면 RC View의 권한 안내에서 설정으로 이동해 카메라를 허용합니다. 앱은 마이크/사진/네트워크 권한을 요청하지 않습니다.

출처: [Apple 개발자 모드](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

## 7. 영상 연결

먼저 출력이 확실한 노트북 HDMI 등으로 캡처카드와 iPad 입력을 검증하면 조종기 출력 문제와 구분하기 쉽습니다.

```text
영상 출력이 확인된 기기 → HDMI 케이블 → UVC 캡처카드 → iPad
```

장치가 하나면 기본적으로 자동 미리보기가 시작됩니다. 여러 장치는 **연결** 탭에서 선택합니다. 프레임 수신 중이어도 HDMI 원본이 정상이라는 뜻은 아닙니다. 검은 화면/No Signal은 원본 출력과 HDMI 연결을 확인합니다.

DJI RC 2 출력 여부는 현재 조종기·펌웨어·어댑터에서 따로 확인해야 합니다. 앱이 출력 기능을 추가하지 않습니다. 일반 USB-C→HDMI 출력 어댑터를 캡처카드 대신 사용할 수 없습니다.

## 8. 7일 갱신과 업데이트

- 주 1회 같은 Apple 계정/Bundle ID로 기존 앱 위에 다시 설치하면 갱신할 수 있습니다. 갱신만 할 때에는 기존 IPA를 재사용하며 GitHub 빌드는 필요 없습니다.
- Sideloadly의 자동 갱신을 켜면 데몬이 만료 전 재서명을 시도합니다. **PC 실행 중 + iPad를 USB 또는 같은 Wi-Fi에서 인식**해야 합니다.
- Wi-Fi 갱신은 USB 연결 후 iTunes 기기 요약에서 **Wi-Fi를 통해 이 iPad 동기화**를 켭니다.
- 만료되면 Windows에 연결해 다시 서명·설치합니다. 앱을 먼저 삭제하지 않아도 됩니다.
- 코드 변경 시 새 IPA를 빌드하고 동일한 계정/Bundle ID로 덮어 설치합니다.
- 앱의 영상 보기는 오프라인으로 동작하지만 설치·갱신에는 인터넷이 필요합니다.

장기간 PC에 접근하지 못하는 환경에서는 7일 만료가 실사용 제약입니다. 무료로 영구 서명되는 앱이라고 설명하지 않습니다.
