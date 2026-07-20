<#
  토스트 클릭 시 실행되는 핸들러 (claude-code-toast: 프로토콜).
  인자로 받은 URI에서 pid를 뽑아 그 프로세스의 메인 창을 포커스한다.
  예: claude-code-toast:focus?pid=1234
#>
param([string]$uri)

$targetPid = 0
if ($uri -match 'pid=(\d+)') { $targetPid = [int]$matches[1] }
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
