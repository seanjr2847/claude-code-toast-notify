' Runs the toast "open" handler without a visible console window.
' Resolves toast-activate.ps1 from THIS script's own folder, so it works
' whether it lives in the plugin root or in ~/.claude.
Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = scriptDir & "\toast-activate.ps1"
uri = ""
If WScript.Arguments.Count > 0 Then uri = WScript.Arguments(0)
cmd = "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & ps1 & """ """ & uri & """"
sh.Run cmd, 0, False
