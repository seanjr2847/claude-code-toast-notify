<#
  Claude Code 완료/입력 알림 → Windows 토스트 설치 스크립트
  하는 일:
   1. notify.ps1 + claude-icon.png 를 ~/.claude 로 복사
   2. AUMID "Claude Code" 레지스트리 등록 (Win11에서 이거 없으면 토스트가 조용히 안 뜸)
   3. ~/.claude/settings.json 에 Notification/Stop 훅 + preferredNotifChannel 병합 (없을 때만)
  idempotent: 여러 번 돌려도 안전. settings.json 은 수정 전 .bak 백업.
#>
$ErrorActionPreference = "Stop"
$src   = $PSScriptRoot
$dest  = Join-Path $env:USERPROFILE ".claude"
if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }

# 1) 파일 복사
Copy-Item (Join-Path $src "notify.ps1")      (Join-Path $dest "notify.ps1")      -Force
Copy-Item (Join-Path $src "claude-icon.png") (Join-Path $dest "claude-icon.png") -Force
Write-Host "[1/3] notify.ps1 + claude-icon.png -> $dest" -ForegroundColor Green

# 2) AUMID 등록
$key = "HKCU:\Software\Classes\AppUserModelId\Claude Code"
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
New-ItemProperty $key -Name DisplayName -Value "Claude Code" -PropertyType String -Force | Out-Null
New-ItemProperty $key -Name IconUri -Value (Join-Path $dest "claude-icon.png") -PropertyType String -Force | Out-Null
New-ItemProperty $key -Name ShowInSettings -Value 1 -PropertyType DWord -Force | Out-Null
Write-Host "[2/3] AUMID 'Claude Code' 레지스트리 등록" -ForegroundColor Green

# 3) settings.json 병합
$settingsPath = Join-Path $dest "settings.json"
$notify = Join-Path $dest "notify.ps1"
function New-Hook($event) {
  $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$notify`" -Event $event"
  [pscustomobject]@{ matcher = ""; hooks = @([pscustomobject]@{ type = "command"; command = $cmd }) }
}
if (Test-Path $settingsPath) {
  Copy-Item $settingsPath "$settingsPath.bak" -Force
  $s = Get-Content $settingsPath -Raw | ConvertFrom-Json
} else {
  $s = [pscustomobject]@{}
}
if (-not $s.PSObject.Properties['hooks']) { $s | Add-Member hooks ([pscustomobject]@{}) -Force }
foreach ($ev in "Notification","Stop") {
  if (-not $s.hooks.PSObject.Properties[$ev]) {
    $s.hooks | Add-Member $ev @(New-Hook $ev) -Force
  }
}
$s | Add-Member preferredNotifChannel "notifications_disabled" -Force
($s | ConvertTo-Json -Depth 100) | Set-Content $settingsPath -Encoding UTF8
Write-Host "[3/3] settings.json 훅 + preferredNotifChannel 병합 (백업: settings.json.bak)" -ForegroundColor Green

Write-Host ""
Write-Host "완료! Claude Code 세션을 재시작하면 적용됩니다." -ForegroundColor Cyan
