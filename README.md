# claude-code-toast-notify

Claude Code(Windows)에서 **작업 완료 / 입력 대기 / 권한 요청** 시 네이티브 Windows 토스트 알림을 띄웁니다. 토스트 제목에 **세션 이름**(rename한 이름 → 자동 제목 → 폴더명)이 표시돼서 세션이 여러 개여도 구분됩니다.

![status](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)

## 무엇을 하나

- `Stop` 훅 → ✅ 완료 / ❌ 에러 / ⏹️ 중단 토스트 (마지막 assistant 메시지 요약을 본문에)
- `Notification` 훅 → 🔐 권한 / ⏳ 입력 대기 토스트
- 실패/권한/대기 → ❌ `StopFailure` · 🔐 `PermissionRequest` · 💤 `TeammateIdle`
- 토스트 제목 = 세션 이름, 하단 = 📁 작업 폴더, 앱 로고 = Claude 아이콘
- 버튼: **[🖥 열기]** = 세션의 터미널 창 포커스 · **[다시 알림]** = 드롭다운에서 5분/30분/1시간 스누즈
- Claude Code 자체 desktop 알림(이름 없는 "작업이 완료되었어요")은 꺼서 중복 제거

### 상태 감지 (❌ / ⏹️)

`Stop` 시 트랜스크립트 꼬리를 훑어 마지막 턴 결과를 판정합니다:
- `is_error` / `isApiErrorMessage` → ❌ 에러
- `[Request interrupted` → ⏹️ 사용자 중단
- 그 외 → ✅ 완료

(꼬리 25줄만 보는 휴리스틱이라 더 앞쪽 에러는 놓칠 수 있음.)

### 버튼

- **[🖥 열기]** — 세션을 소유한 터미널 창을 앞으로 가져옵니다. WezTerm이면 `WEZTERM_PANE`+GUI 소켓을 토스트에 실어 `wezterm cli activate-pane`로 그 페인을 포커스하고, 그 외엔 창 단위 포커스(`SetForegroundWindow` + AttachThreadInput 우회). 핸들러는 `toast-activate.vbs`(wscript)로 콘솔 창 없이 실행됩니다.
  - **한계**: Claude 에이전트 팀처럼 한 페인 안에서 여러 세션이 도는 in-process 구성은, 그 페인(=Claude 창)까지만 포커스되고 특정 팀원 세션 개별 지목은 불가합니다(Claude Code가 외부 포커스 API를 제공하지 않음).
- **[다시 알림]** — 드롭다운(5분/30분/1시간)에서 고른 시간 뒤 같은 토스트를 다시 띄우는 Windows 네이티브 스누즈.

## 설치 (플러그인 · 권장)

Claude Code 안에서:

```
/plugin marketplace add seanjr2847/claude-code-toast-notify
/plugin install toast-notify
```

그러면 훅이 플러그인에서 바로 제공되고(`settings.json` 안 건드림), 세션 시작 시 `setup.ps1`이 AUMID·프로토콜을 등록합니다. 끄려면 `/plugin` 에서 비활성화.

> 플러그인과 아래 스크립트 설치를 **동시에 쓰지 마세요** — 알림이 두 번 뜹니다. 스크립트로 이미 깔았다면 `uninstall.ps1` 먼저 실행.

## 설치 (스크립트 · 폴백)

PowerShell에서:

```powershell
git clone https://github.com/seanjr2847/claude-code-toast-notify.git
cd claude-code-toast-notify
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

그 다음 **Claude Code 세션을 재시작**하면 적용됩니다.

`install.ps1`이 하는 일 (idempotent, 여러 번 실행 안전):

1. `notify.ps1` + `toast-activate.ps1/.vbs` + `claude-icon.png` → `~/.claude/` 복사
2. **AUMID `Claude Code` 레지스트리 등록** — Windows 11에서 이게 없으면 토스트가 에러 없이 조용히 안 뜹니다 (파일 복사로는 안 넘어오는 부분)
3. **`claude-code-toast:` 프로토콜 등록** — [열기] 버튼이 창을 포커스하는 데 사용
4. `~/.claude/settings.json`에 알림 훅 + `preferredNotifChannel: notifications_disabled` 병합 (기존 설정은 보존, 수정 전 `settings.json.bak` 백업)

## 요구 사항

- Windows 10/11, PowerShell 5+
- Claude Code (native 설치)
- Windows 알림이 켜져 있고 집중 지원(Do Not Disturb)이 배너를 막고 있지 않을 것

## 토스트가 안 뜰 때

1. **AUMID 등록 확인** — 대부분의 원인. `install.ps1` 재실행 또는 수동:
   ```powershell
   $key = "HKCU:\Software\Classes\AppUserModelId\Claude Code"
   New-Item $key -Force | Out-Null
   New-ItemProperty $key DisplayName "Claude Code" -Force | Out-Null
   New-ItemProperty $key IconUri "$env:USERPROFILE\.claude\claude-icon.png" -Force | Out-Null
   ```
   ※ Windows 업데이트가 이 키를 지우기도 함 → 재발 시 여기부터.
2. **집중 지원** 이 배너를 알림 센터로만 보내고 있지 않은지 (작업 표시줄 오른쪽 끝 확인)
3. 훅 설정은 **세션 시작 때만 로드** — 설정 바꿨으면 세션 재시작

## 커스터마이즈

`notify.ps1`의 세션 이름 우선순위는 `Get-SessionName`에서: rename 이름(`customTitle`) → 자동 제목(`aiTitle`) → 폴더명. 이모지/문구는 `switch ($Event)` 블록에서, 스누즈 시간은 `snoozeTime` selection에서 수정.

## 기존 설정을 해치지 않음 (non-destructive)

`install.ps1`은 남의 `settings.json`을 덮어쓰지 않습니다:
- 알림 훅은 **해당 이벤트 훅이 없을 때만** 추가 (이미 자기 훅이 있으면 그대로 둠)
- `preferredNotifChannel`은 **값이 없을 때만** `notifications_disabled` 설정 (이미 값이 있으면 그 값 유지)
- 나머지 키(`model`, `permissions`, `env` 등)는 전부 보존, 수정 전 `settings.json.bak` 백업
- `settings.json`이 깨져 파싱 안 되면 **손대지 않고** 건너뜀

## 제거

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

`notify.ps1`을 가리키는 알림 훅만 제거하고, 파일·AUMID·프로토콜을 정리합니다. 다른 훅/설정은 보존합니다. (`preferredNotifChannel`은 우리가 설정했는지 확신할 수 없어 보존 — 원치 않으면 직접 지우세요.)

## 다른 사람에게 배포할 때

1. 리포를 clone 또는 zip으로 전달 (또는 이 리포를 fork)
2. 받는 사람은 PowerShell에서 `install.ps1` 한 번 실행 → 세션 재시작
3. Windows 10/11 전용. 관리자 권한 불필요(전부 HKCU + 사용자 프로필)

**언어**: 토스트 문구가 한국어입니다(`notify.ps1`의 `switch ($Event)` 블록). 영어권에 배포하려면 그 블록의 문자열만 바꾸면 됩니다.

## 수동 설정 (install.ps1이 settings.json을 못 건드릴 때)

`~/.claude/settings.json`에 아래를 직접 병합하세요(경로의 `<USER>`는 본인 계정으로):

```json
{
  "preferredNotifChannel": "notifications_disabled",
  "hooks": {
    "Stop":          [{ "matcher": "", "hooks": [{ "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"%USERPROFILE%\.claude\notify.ps1\" -Event Stop" }] }],
    "Notification":  [{ "matcher": "", "hooks": [{ "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"%USERPROFILE%\.claude\notify.ps1\" -Event Notification" }] }]
  }
}
```
