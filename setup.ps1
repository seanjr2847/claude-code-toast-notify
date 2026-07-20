<#
  플러그인 SessionStart 셋업: AUMID + claude-code-toast 프로토콜 등록,
  preferredNotifChannel(없을 때만) 설정. 매 세션 재등록해 플러그인 경로 변경(업데이트)에도 자가치유.
  세션 시작을 절대 깨지 않도록 조용히 실패한다.
#>
$ErrorActionPreference = "SilentlyContinue"
$root = $PSScriptRoot

# AUMID (아이콘/표시명)
$key = "HKCU:\Software\Classes\AppUserModelId\Claude Code"
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
New-ItemProperty $key -Name DisplayName -Value "Claude Code" -PropertyType String -Force | Out-Null
$icon = Join-Path $root "claude-icon.png"
if (Test-Path $icon) { New-ItemProperty $key -Name IconUri -Value $icon -PropertyType String -Force | Out-Null }
New-ItemProperty $key -Name ShowInSettings -Value 1 -PropertyType DWord -Force | Out-Null

# 클릭 [열기] 프로토콜
$proto = "HKCU:\Software\Classes\claude-code-toast"
New-Item $proto -Force | Out-Null
Set-Item $proto -Value "URL:Claude Code Toast"
New-ItemProperty $proto -Name "URL Protocol" -Value "" -PropertyType String -Force | Out-Null
$cmdkey = "$proto\shell\open\command"
New-Item $cmdkey -Force | Out-Null
$vbs = Join-Path $root "toast-activate.vbs"
Set-Item $cmdkey -Value ("wscript.exe `"$vbs`" `"%1`"")

# preferredNotifChannel: 값 없을 때만 (기존 설정 보존)
$sp = Join-Path $env:USERPROFILE ".claude\settings.json"
if (Test-Path $sp) {
  try {
    $s = Get-Content $sp -Raw | ConvertFrom-Json
    if (-not $s.PSObject.Properties['preferredNotifChannel']) {
      $s | Add-Member preferredNotifChannel "notifications_disabled" -Force
      ($s | ConvertTo-Json -Depth 100) | Set-Content $sp -Encoding UTF8
    }
  } catch {}
}
