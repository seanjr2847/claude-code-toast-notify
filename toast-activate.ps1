<#
  토스트 클릭/버튼 시 실행되는 핸들러 (claude-code-toast: 프로토콜).
  URI에서 pid + (선택)pane 을 뽑아 해당 세션으로 포커스한다.
  예: claude-code-toast:focus?pid=1234&pane=7
  - pane 있으면(WezTerm) 그 페인을 정확히 activate
  - pid 로 터미널 창을 OS foreground 로 끌어올림
#>
param([string]$uri)

$targetPid = 0
if ($uri -match 'pid=(\d+)') { $targetPid = [int]$matches[1] }
$pane = $null
if ($uri -match 'pane=(\d+)') { $pane = $matches[1] }
$sock = $null
if ($uri -match 'sock=([^&]+)') { $sock = [uri]::UnescapeDataString($matches[1]) }

# WezTerm 페인 단위 포커스 (창 안에서 정확한 세션 탭/페인 선택)
# sock을 세팅해야 실행 중인 GUI에 붙음 — 없으면 새 창이 뜨거나 연결 실패
if ($pane) {
  if ($sock) { $env:WEZTERM_UNIX_SOCKET = $sock }
  try { wezterm cli activate-pane --pane-id $pane 2>$null } catch {}
}

if ($targetPid -le 0) { return }

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class ToastWin {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
}
'@

try {
  $p = Get-Process -Id $targetPid -ErrorAction Stop
  $h = $p.MainWindowHandle
  if ($h -ne [IntPtr]::Zero) {
    if ([ToastWin]::IsIconic($h)) { [ToastWin]::ShowWindow($h, 9) | Out-Null }  # SW_RESTORE
    # ponytail: SetForegroundWindow can be refused under focus-steal rules; good enough for a click-initiated call
    [ToastWin]::SetForegroundWindow($h) | Out-Null
  }
} catch {}
