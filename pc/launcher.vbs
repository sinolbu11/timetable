' 내 시간표 실행 - 창 없이 트레이 앱을 시작해요. (더블클릭)
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = dir & "\timetable_tray.ps1"
If Not fso.FileExists(ps1) Then
  MsgBox "timetable_tray.ps1 파일이 같은 폴더에 있어야 해요.", 48, "내 시간표"
  WScript.Quit
End If
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & ps1 & """"
CreateObject("WScript.Shell").Run cmd, 0, False
