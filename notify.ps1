param([string]$Event = "Notification")

# Read hook event JSON from stdin
$raw = [Console]::In.ReadToEnd()
$data = $null
try { $data = $raw | ConvertFrom-Json } catch {}
$msg = $data.message

function Get-Recap($path) {
  if (-not $path -or -not (Test-Path $path)) { return $null }
  $lines = Get-Content $path -Tail 60 -Encoding UTF8
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    $o = $null
    try { $o = $lines[$i] | ConvertFrom-Json } catch { continue }
    if ($o.type -eq "assistant") {
      $t = ($o.message.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join " "
      $t = ($t -replace '\s+', ' ').Trim()
      if ($t) { return $t }
    }
  }
  return $null
}

# Session name: manual rename (customTitle) > auto (aiTitle) > null. Last occurrence wins.
function Get-SessionName($path) {
  if (-not $path -or -not (Test-Path $path)) { return $null }
  $ct = $null; $at = $null
  foreach ($line in [System.IO.File]::ReadLines($path)) {
    if ($line -notmatch '"(customTitle|aiTitle)"') { continue }
    $o = $null
    try { $o = $line | ConvertFrom-Json } catch { continue }
    if ($o.customTitle) { $ct = $o.customTitle }
    elseif ($o.aiTitle) { $at = $o.aiTitle }
  }
  if ($ct) { return $ct } elseif ($at) { return $at } else { return $null }
}

# Turn outcome: error / interrupted / ok. Heuristic string scan of the tail.
# ponytail: scans last 25 lines only; an error further back is missed (upgrade: parse full turn)
function Get-TurnStatus($path) {
  if (-not $path -or -not (Test-Path $path)) { return "ok" }
  $lines = Get-Content $path -Tail 25 -Encoding UTF8
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    $l = $lines[$i]
    if ($l -match '\[Request interrupted') { return "interrupted" }
    if ($l -match '"isApiErrorMessage"\s*:\s*true') { return "error" }
    if ($l -match '"is_error"\s*:\s*true')          { return "error" }
  }
  return "ok"
}

# Terminal window PID: walk up the parent process chain to the first ancestor with a visible window.
# Used as the click target so tapping the toast focuses that terminal.
function Get-TerminalPid {
  $cur = $PID
  for ($i = 0; $i -lt 12; $i++) {
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -ErrorAction SilentlyContinue
    if (-not $proc) { break }
    $parent = $proc.ParentProcessId
    if (-not $parent -or $parent -eq 0) { break }
    try {
      $pobj = Get-Process -Id $parent -ErrorAction Stop
      if ($pobj.MainWindowHandle -ne 0) { return $parent }
    } catch {}
    $cur = $parent
  }
  return $null
}

# Pick emoji / body / sound per situation (title = session name, set below)
switch ($Event) {
  "Stop" {
    $recap = Get-Recap $data.transcript_path
    switch (Get-TurnStatus $data.transcript_path) {
      "error"       { $emoji = "❌"; $sound = "ms-winsoundevent:Notification.Reminder"; $fallback = "에러로 중단됐어요." }
      "interrupted" { $emoji = "⏹️"; $sound = "ms-winsoundevent:Notification.IM";       $fallback = "사용자가 중단했어요." }
      default       { $emoji = "✅"; $sound = "ms-winsoundevent:Notification.Default";  $fallback = "작업을 마쳤어요." }
    }
    $body = if ($recap) { $recap } else { $fallback }
  }
  "StopFailure" {
    $emoji = "❌"
    $body  = if ($msg) { $msg } else { "턴이 실패로 끝났어요." }
    $sound = "ms-winsoundevent:Notification.Reminder"
  }
  "PermissionRequest" {
    $emoji = "🔐"
    $body  = if ($msg) { $msg } else { "권한 승인을 기다리는 중이에요." }
    $sound = "ms-winsoundevent:Notification.Reminder"
  }
  "TeammateIdle" {
    $emoji = "💤"
    $body  = "팀 에이전트가 대기 중이에요."
    $sound = "ms-winsoundevent:Notification.IM"
  }
  default {
    if ($msg -match "permission|approve|allow") {
      $emoji = "🔐"
      $body  = "도구 사용 권한 승인을 기다리는 중이에요."
      $sound = "ms-winsoundevent:Notification.Reminder"
    } else {
      $emoji = "⏳"
      $body  = "입력을 기다리는 중이에요."
      $sound = "ms-winsoundevent:Notification.IM"
    }
  }
}

# Title = session name (rename > ai title) > folder; emoji = status
$sess = Get-SessionName $data.transcript_path
if (-not $sess) { $sess = if ($data.cwd) { Split-Path $data.cwd -Leaf } else { "Claude Code" } }
$title = "$emoji $sess"

# Trim body to a toast-friendly length
if ($body.Length -gt 180) { $body = $body.Substring(0, 180).TrimEnd() + "…" }

[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
$doc = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$texts = $doc.GetElementsByTagName("text")
$texts.Item(0).AppendChild($doc.CreateTextNode($title)) | Out-Null
$texts.Item(1).AppendChild($doc.CreateTextNode($body)) | Out-Null

# Upgrade to generic template so attribution + logo render nicely
$binding = $doc.GetElementsByTagName("binding").Item(0)
$binding.SetAttribute("template", "ToastGeneric")

# Attribution (bottom): working-dir folder, since session name is now the title
$proj = if ($data.cwd) { Split-Path $data.cwd -Leaf } else { "" }
if ($proj) {
  $attr = $doc.CreateElement("text")
  $attr.SetAttribute("placement", "attribution")
  $attr.AppendChild($doc.CreateTextNode("📁 " + $proj)) | Out-Null
  $binding.AppendChild($attr) | Out-Null
}

# App logo (Claude sunburst), cropped to a circle
$icon = "$env:USERPROFILE\.claude\claude-icon.png"
if (Test-Path $icon) {
  $img = $doc.CreateElement("image")
  $img.SetAttribute("placement", "appLogoOverride")
  $img.SetAttribute("hint-crop", "circle")
  $img.SetAttribute("src", "file:///" + ($icon -replace '\\', '/'))
  $doc.GetElementsByTagName("binding").Item(0).AppendChild($img) | Out-Null
}

$audio = $doc.CreateElement("audio")
$audio.SetAttribute("src", $sound)
$doc.DocumentElement.AppendChild($audio) | Out-Null

# Click / buttons: focus this session. On WezTerm we focus the exact pane, else the terminal window.
# (protocol activation — no COM activator needed)
$termPid = Get-TerminalPid
if ($termPid) {
  $focusArgs = "claude-code-toast:focus?pid=$termPid"
  if ($env:WEZTERM_PANE) { $focusArgs += "&pane=$($env:WEZTERM_PANE)" }
  $doc.DocumentElement.SetAttribute("launch", $focusArgs)
  $doc.DocumentElement.SetAttribute("activationType", "protocol")

  # Action buttons (canonical toast order: visual, audio, actions)
  $actions = $doc.CreateElement("actions")
  $open = $doc.CreateElement("action")
  $open.SetAttribute("content", "🖥 열기"); $open.SetAttribute("arguments", $focusArgs); $open.SetAttribute("activationType", "protocol")
  $actions.AppendChild($open) | Out-Null
  $dismiss = $doc.CreateElement("action")
  $dismiss.SetAttribute("content", "무시"); $dismiss.SetAttribute("arguments", "dismiss"); $dismiss.SetAttribute("activationType", "system")
  $actions.AppendChild($dismiss) | Out-Null
  $doc.DocumentElement.AppendChild($actions) | Out-Null
}

$toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Claude Code").Show($toast)
