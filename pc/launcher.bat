@echo off
rem 내 시간표 (트레이 앱) 실행 - vbs 파일을 쓸 수 없을 때만 사용
if exist "%~dp0내 시간표 실행.vbs" (
  start "" wscript.exe "%~dp0내 시간표 실행.vbs"
  exit /b
)
start "" conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0timetable_tray.ps1"
