# Toast click/button handler (claude-code-toast: protocol).
# Parses pid + optional pane/sock from the URI and focuses that session.
#   claude-code-toast:focus?pid=1234&pane=7&sock=<enc>
# Diagnostic log: ~/.claude/toast-activate.log
param([string]$uri)

$log = Join-Path $env:USERPROFILE ".claude\toast-activate.log"
function Log($m) { try { Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m) -Encoding UTF8 } catch {} }

$targetPid = 0; if ($uri -match 'pid=(\d+)')   { $targetPid = [int]$matches[1] }
$pane = $null;  if ($uri -match 'pane=(\d+)')  { $pane = $matches[1] }
$sock = $null;  if ($uri -match 'sock=([^&]+)') { $sock = [uri]::UnescapeDataString($matches[1]) }
Log "CLICK uri=$uri"
Log "  parsed: pid=$targetPid pane=$pane sockSet=$([bool]$sock)"

# Run a process with a timeout so a dead wezterm socket cannot hang the handler.
function Invoke-WithTimeout($file, $arguments, $ms) {
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo.FileName = $file
  $p.StartInfo.Arguments = $arguments
  $p.StartInfo.UseShellExecute = $false   # inherit current env (incl. WEZTERM_UNIX_SOCKET)
  $p.StartInfo.CreateNoWindow = $true
  $null = $p.Start()
  if ($p.WaitForExit($ms)) { return $p.ExitCode }
  try { $p.Kill() } catch {}
  return -1   # timed out
}

# 1) WezTerm: focus the exact pane (sock must be set to reach the running GUI)
$paneOk = $false
if ($pane) {
  if ($sock) { $env:WEZTERM_UNIX_SOCKET = $sock }
  $code = Invoke-WithTimeout "wezterm" "cli activate-pane --pane-id $pane" 2500
  $paneOk = ($code -eq 0)
  Log "  activate-pane pane=$pane ok=$paneOk code=$code"
}

# 2) Raise the terminal window. Candidates: gui pid from sock name > passed pid.
# SetForegroundWindow alone is refused by Windows focus-steal prevention when called
# from a toast-launched process. Force() uses the AttachThreadInput + ALT-key trick to bypass it.
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class ToastWin {
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr pid);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);

  public static bool Force(IntPtr hWnd) {
    if (hWnd == IntPtr.Zero) return false;
    uint fgThread = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero);
    uint thisThread = GetCurrentThreadId();
    keybd_event(0x12, 0, 0, IntPtr.Zero);            // ALT down: unlocks foreground change
    ShowWindow(hWnd, 9);                             // SW_RESTORE
    AttachThreadInput(thisThread, fgThread, true);
    BringWindowToTop(hWnd);
    bool r = SetForegroundWindow(hWnd);
    AttachThreadInput(thisThread, fgThread, false);
    keybd_event(0x12, 0, 2, IntPtr.Zero);            // ALT up (KEYEVENTF_KEYUP)
    return r;
  }
}
'@

$candidates = @()
if ($sock -and $sock -match 'gui-sock-(\d+)') { $candidates += [int]$matches[1] }
if ($targetPid -gt 0) { $candidates += $targetPid }
$candidates = $candidates | Select-Object -Unique

$focused = $false
foreach ($cp in $candidates) {
  try {
    $proc = Get-Process -Id $cp -ErrorAction Stop
    $h = $proc.MainWindowHandle
    if ($h -ne [IntPtr]::Zero) {
      $r = [ToastWin]::Force($h)
      Log "  focus pid=$cp ($($proc.ProcessName)) hwnd=$h force=$r"
      $focused = $true; break
    } else { Log "  pid=$cp ($($proc.ProcessName)) has no MainWindowHandle" }
  } catch { Log "  pid=$cp not running" }
}
if (-not $focused -and -not $paneOk) { Log "  RESULT: FAILED (no focus target)" } else { Log "  RESULT: ok (pane=$paneOk window=$focused)" }
