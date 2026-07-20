<#
  Claude Code 완료/입력 알림 → Windows 토스트 설치 스크립트
  비파괴적(non-destructive): 기존 settings.json 값은 보존하고, 없는 것만 추가한다.
   1. notify.ps1 + toast-activate.ps1/.vbs + claude-icon.png 를 ~/.claude 로 복사
   2. AUMID "Claude Code" 레지스트리 등록 (Win11에서 이거 없으면 토스트가 조용히 안 뜸)
   3. claude-code-toast: 프로토콜 등록 (토스트 [열기] 버튼 → 터미널 창 포커스)
   4. ~/.claude/settings.json 에 알림 훅 + preferredNotifChannel 병합 (이미 있으면 건드리지 않음)
  idempotent: 여러 번 돌려도 안전. settings.json 은 수정 전 .bak 백업.
#>
$ErrorActionPreference = "Stop"
$src   = $PSScriptRoot
$dest  = Join-Path $env:USERPROFILE ".claude"
if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }

# 1) 파일 복사
Copy-Item (Join-Path $src "notify.ps1")         (Join-Path $dest "notify.ps1")         -Force
Copy-Item (Join-Path $src "toast-activate.ps1") (Join-Path $dest "toast-activate.ps1") -Force
Copy-Item (Join-Path $src "toast-activate.vbs") (Join-Path $dest "toast-activate.vbs") -Force
Copy-Item (Join-Path $src "claude-icon.png")    (Join-Path $dest "claude-icon.png")    -Force
Write-Host "[1/4] notify.ps1 + toast-activate.ps1/.vbs + claude-icon.png -> $dest" -ForegroundColor Green

# 2) AUMID 등록 (HKCU, 추가만 — 기존에 영향 없음)
$key = "HKCU:\Software\Classes\AppUserModelId\Claude Code"
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
New-ItemProperty $key -Name DisplayName -Value "Claude Code" -PropertyType String -Force | Out-Null
New-ItemProperty $key -Name IconUri -Value (Join-Path $dest "claude-icon.png") -PropertyType String -Force | Out-Null
New-ItemProperty $key -Name ShowInSettings -Value 1 -PropertyType DWord -Force | Out-Null
Write-Host "[2/4] AUMID 'Claude Code' 레지스트리 등록" -ForegroundColor Green

# 3) 클릭 시 창 포커스용 프로토콜 등록 (claude-code-toast:, HKCU 전용)
$proto = "HKCU:\Software\Classes\claude-code-toast"
New-Item $proto -Force | Out-Null
Set-Item $proto -Value "URL:Claude Code Toast"
New-ItemProperty $proto -Name "URL Protocol" -Value "" -PropertyType String -Force | Out-Null
$cmdkey = "$proto\shell\open\command"
New-Item $cmdkey -Force | Out-Null
$vbs = Join-Path $dest "toast-activate.vbs"
Set-Item $cmdkey -Value ("wscript.exe `"$vbs`" `"%1`"")
Write-Host "[3/4] claude-code-toast 프로토콜 등록 ([열기] 버튼용)" -ForegroundColor Green

# 4) settings.json 병합 — 비파괴적
$settingsPath = Join-Path $dest "settings.json"
$notify = Join-Path $dest "notify.ps1"
function New-Hook($event) {
  $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$notify`" -Event $event"
  [pscustomobject]@{ matcher = ""; hooks = @([pscustomobject]@{ type = "command"; command = $cmd }) }
}

if (Test-Path $settingsPath) {
  try {
    $s = Get-Content $settingsPath -Raw | ConvertFrom-Json
  } catch {
    Write-Host "[4/4] settings.json 을 파싱하지 못해 건드리지 않았습니다." -ForegroundColor Yellow
    Write-Host "      README의 '수동 설정' 블록을 직접 추가하세요." -ForegroundColor Yellow
    return
  }
  Copy-Item $settingsPath "$settingsPath.bak" -Force
} else {
  $s = [pscustomobject]@{}
}

if (-not $s.PSObject.Properties['hooks']) { $s | Add-Member hooks ([pscustomobject]@{}) -Force }
$events = "Notification","Stop","StopFailure","PermissionRequest","TeammateIdle"
$addedHooks = @()
foreach ($ev in $events) {
  if (-not $s.hooks.PSObject.Properties[$ev]) {
    $s.hooks | Add-Member $ev @(New-Hook $ev) -Force   # 기존 훅이 있으면 건드리지 않음
    $addedHooks += $ev
  }
}

# preferredNotifChannel: 기존 값이 있으면 존중, 없을 때만 설정
$channelMsg = ""
if (-not $s.PSObject.Properties['preferredNotifChannel']) {
  $s | Add-Member preferredNotifChannel "notifications_disabled" -Force
  $channelMsg = "preferredNotifChannel=notifications_disabled 추가"
} else {
  $channelMsg = "preferredNotifChannel 기존값 유지($($s.preferredNotifChannel))"
}

($s | ConvertTo-Json -Depth 100) | Set-Content $settingsPath -Encoding UTF8
$hookMsg = if ($addedHooks.Count) { "훅 추가: $($addedHooks -join ',')" } else { "훅 이미 존재(변경 없음)" }
Write-Host "[4/4] settings.json 병합 — $hookMsg · $channelMsg (백업: settings.json.bak)" -ForegroundColor Green

Write-Host ""
Write-Host "완료! Claude Code 세션을 재시작하면 적용됩니다." -ForegroundColor Cyan
