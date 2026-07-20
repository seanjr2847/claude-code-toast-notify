# claude-code-toast-notify

Claude Code(Windows)에서 **작업 완료 / 입력 대기 / 권한 요청** 시 네이티브 Windows 토스트 알림을 띄웁니다. 토스트 제목에 **세션 이름**(rename한 이름 → 자동 제목 → 폴더명)이 표시돼서 세션이 여러 개여도 구분됩니다.

![status](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)

## 무엇을 하나

- `Stop` 훅 → ✅ 완료 / ❌ 에러 / ⏹️ 중단 토스트 (마지막 assistant 메시지 요약을 본문에)
- `Notification` 훅 → 🔐 권한 / ⏳ 입력 대기 토스트
- 실패/권한/대기 → ❌ `StopFailure` · 🔐 `PermissionRequest` · 💤 `TeammateIdle`
- 토스트 제목 = 세션 이름, 하단 = 📁 작업 폴더, 앱 로고 = Claude 아이콘
- **토스트 클릭 → 해당 세션 터미널 창으로 포커스** (`claude-code-toast:` 프로토콜)
- Claude Code 자체 desktop 알림(이름 없는 "작업이 완료되었어요")은 꺼서 중복 제거

### 상태 감지 (❌ / ⏹️)

`Stop` 시 트랜스크립트 꼬리를 훑어 마지막 턴 결과를 판정합니다:
- `is_error` / `isApiErrorMessage` → ❌ 에러
- `[Request interrupted` → ⏹️ 사용자 중단
- 그 외 → ✅ 완료

(꼬리 25줄만 보는 휴리스틱이라 더 앞쪽 에러는 놓칠 수 있음.)

### 클릭 → 창 포커스

토스트를 클릭하면 세션을 소유한 터미널 창이 앞으로 나옵니다. `notify.ps1`이 부모 프로세스 체인을 거슬러 창을 가진 터미널의 PID를 찾아 토스트에 심고, 클릭 시 `toast-activate.ps1`이 그 창을 `SetForegroundWindow`로 올립니다. COM activator 없이 URI 프로토콜 activation만 사용 — PowerShell 생성 토스트에서 동작하는 방식.

## 설치

PowerShell에서:

```powershell
git clone https://github.com/seanjr2847/claude-code-toast-notify.git
cd claude-code-toast-notify
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

그 다음 **Claude Code 세션을 재시작**하면 적용됩니다.

`install.ps1`이 하는 일 (idempotent, 여러 번 실행 안전):

1. `notify.ps1` + `toast-activate.ps1` + `claude-icon.png` → `~/.claude/` 복사
2. **AUMID `Claude Code` 레지스트리 등록** — Windows 11에서 이게 없으면 토스트가 에러 없이 조용히 안 뜹니다 (파일 복사로는 안 넘어오는 부분)
3. **`claude-code-toast:` 프로토콜 등록** — 토스트 클릭 시 창 포커스용
4. `~/.claude/settings.json`에 훅 2개 + `preferredNotifChannel: notifications_disabled` 병합 (기존 설정은 보존, 수정 전 `settings.json.bak` 백업)

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

`notify.ps1`의 세션 이름 우선순위는 `Get-SessionName`에서: rename 이름(`customTitle`) → 자동 제목(`aiTitle`) → 폴더명. 이모지/문구는 `switch ($Event)` 블록에서 수정.
