# Toast "open" handler (claude-code-toast: protocol).
# Parses pid + optional pane/sock and focuses that session's terminal window.
#   claude-code-toast:focus?pid=1234&pane=7&sock=<enc>
param([string]$uri)

$targetPid = 0; if ($uri -match 'pid=(\d+)')    { $targetPid = [int]$matches[1] }
$pane = $null;  if ($uri -match 'pane=(\d+)')   { $pane = $matches[1] }
$sock = $null;  if ($uri -match 'sock=([^&]+)') { $sock = [uri]::UnescapeDataString($matches[1]) }

# Run a process with a timeout so a dead wezterm socket cannot hang the handler.
function Invoke-WithTimeout($file, $arguments, $ms) {
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo.FileName = $file
  $p.StartInfo.Arguments = $arguments
  $p.StartInfo.UseShellExecute = $false   # inherit env (incl. WEZTERM_UNIX_SOCKET)
  $p.StartInfo.CreateNoWindow = $true
  $null = $p.Start()
  if ($p.WaitForExit($ms)) { return $p.ExitCode }
  try { $p.Kill() } catch {}
  return -1
}

# WezTerm: focus the exact pane (sock must be set to reach the running GUI)
if ($pane) {
  if ($sock) { $env:WEZTERM_UNIX_SOCKET = $sock }
  Invoke-WithTimeout "wezterm" "cli activate-pane --pane-id $pane" 2500 | Out-Null
}

# Raise the terminal window to the foreground. SetForegroundWindow alone is refused by
# Windows focus-steal prevention from a toast-launched process; Force() bypasses it.
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
    uint fg = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero);
    uint me = GetCurrentThreadId();
    keybd_event(0x12, 0, 0, IntPtr.Zero);       // ALT down: unlocks foreground change
    ShowWindow(hWnd, 9);                         // SW_RESTORE
    AttachThreadInput(me, fg, true);
    BringWindowToTop(hWnd);
    bool r = SetForegroundWindow(hWnd);
    AttachThreadInput(me, fg, false);
    keybd_event(0x12, 0, 2, IntPtr.Zero);        // ALT up
    return r;
  }
}
'@

# Candidates: gui pid from sock name > passed pid.
$candidates = @()
if ($sock -and $sock -match 'gui-sock-(\d+)') { $candidates += [int]$matches[1] }
if ($targetPid -gt 0) { $candidates += $targetPid }
foreach ($cp in ($candidates | Select-Object -Unique)) {
  try {
    $proc = Get-Process -Id $cp -ErrorAction Stop
    if ($proc.MainWindowHandle -ne [IntPtr]::Zero) { [ToastWin]::Force($proc.MainWindowHandle) | Out-Null; break }
  } catch {}
}
