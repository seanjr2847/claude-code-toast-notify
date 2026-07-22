<#
  제거 스크립트: 이 도구가 추가한 것만 되돌린다. 다른 설정/훅은 보존한다.
  - notify.ps1 / toast-activate.ps1 / toast-activate.vbs 삭제
  - AUMID + claude-code-toast 프로토콜 레지스트리 제거 (HKCU)
  - settings.json 에서 notify.ps1 을 가리키는 알림 훅만 제거 (.bak 백업)
  preferredNotifChannel 은 우리가 설정했는지 확신할 수 없어 보존한다(필요시 직접 제거).
#>
$ErrorActionPreference = "Stop"
$dest = Join-Path $env:USERPROFILE ".claude"

foreach ($f in "notify.ps1","toast-activate.ps1","toast-activate.vbs") {
  $p = Join-Path $dest $f
  if (Test-Path $p) { Remove-Item $p -Force }
}
Write-Host "[1/3] 스크립트 파일 삭제" -ForegroundColor Green

foreach ($k in @("HKCU:\Software\Classes\AppUserModelId\Claude Code","HKCU:\Software\Classes\claude-code-toast")) {
  if (Test-Path $k) { Remove-Item $k -Recurse -Force }
}
Write-Host "[2/3] AUMID + 프로토콜 레지스트리 제거" -ForegroundColor Green

$settingsPath = Join-Path $dest "settings.json"
if (Test-Path $settingsPath) {
  try {
    $s = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Copy-Item $settingsPath "$settingsPath.bak" -Force
    if ($s.PSObject.Properties['hooks']) {
      foreach ($ev in "Notification","Stop","StopFailure","PermissionRequest","TeammateIdle") {
        if ($s.hooks.PSObject.Properties[$ev]) {
          $json = ($s.hooks.$ev | ConvertTo-Json -Depth 10)
          if ($json -match 'notify\.ps1') { $s.hooks.PSObject.Properties.Remove($ev) }
        }
      }
    }
    ($s | ConvertTo-Json -Depth 100) | Set-Content $settingsPath -Encoding UTF8
    Write-Host "[3/3] settings.json 알림 훅 제거 (preferredNotifChannel은 보존)" -ForegroundColor Green
  } catch {
    Write-Host "[3/3] settings.json 파싱 실패 — 손대지 않음" -ForegroundColor Yellow
  }
}
Write-Host "완료. 세션 재시작하면 반영됩니다." -ForegroundColor Cyan
