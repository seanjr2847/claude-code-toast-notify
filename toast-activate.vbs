' Runs the toast "open" handler without a visible console window.
' (protocol-launched powershell would otherwise flash a console)
Set sh = CreateObject("WScript.Shell")
ps1 = sh.ExpandEnvironmentStrings("%USERPROFILE%") & "\.claude\toast-activate.ps1"
uri = ""
If WScript.Arguments.Count > 0 Then uri = WScript.Arguments(0)
cmd = "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & ps1 & """ """ & uri & """"
sh.Run cmd, 0, False
