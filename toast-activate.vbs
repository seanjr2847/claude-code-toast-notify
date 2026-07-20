' 토스트 클릭/버튼 핸들러를 콘솔 창 없이 실행하는 런처.
' powershell을 프로토콜에서 직접 부르면 새 콘솔 창이 뜨므로, 이걸 거쳐 숨김 실행한다.
Set sh = CreateObject("WScript.Shell")
ps1 = sh.ExpandEnvironmentStrings("%USERPROFILE%") & "\.claude\toast-activate.ps1"
uri = ""
If WScript.Arguments.Count > 0 Then uri = WScript.Arguments(0)
cmd = "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & ps1 & """ """ & uri & """"
sh.Run cmd, 0, False   ' 0 = 창 숨김
