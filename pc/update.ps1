# 내 시간표 PC 프로그램 - 업데이트/설치 도우미 (업데이트.bat 이 내려받아 실행해요)
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
Add-Type -AssemblyName System.Windows.Forms
$Base = 'https://sinolbu11.github.io/timetable/pc/'
$Files = @(@('timetable_tray.ps1', 'timetable_tray.ps1'), @('launcher.vbs', '내 시간표 실행.vbs'), @('launcher.bat', '내 시간표 실행.bat'), @('README.txt', '사용법.txt'))
function Msg([string]$t, [string]$kind = 'Information') { [void][System.Windows.Forms.MessageBox]::Show($t, '내 시간표 업데이트', 'OK', $kind) }

try {
# 1) 설치 폴더 찾기: 실행 중인 프로그램 → 시작 프로그램 바로가기 → 흔한 폴더 검색
$dir = ''
try {
  $procs = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*timetable_tray.ps1*' }
  foreach ($p in $procs) { if ($p.CommandLine -match '"([^"]*timetable_tray\.ps1)"') { $dir = Split-Path $Matches[1] } }
} catch { }
if (-not $dir) {
  try {
    $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) '내 시간표.lnk'
    if (Test-Path $lnk) {
      $sc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
      $cand = @($sc.TargetPath, $sc.Arguments) -join ' '
      if ($cand -match '"?([^"]*\\)(timetable_tray\.ps1|내 시간표 실행\.vbs|내 시간표 실행\.bat)') { $dir = $Matches[1].TrimEnd('\') }
    }
  } catch { }
}
if (-not $dir) {
  foreach ($root in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'), (Join-Path $env:USERPROFILE 'Downloads'), $env:USERPROFILE)) {
    if (-not (Test-Path $root)) { continue }
    $hit = Get-ChildItem -Path $root -Filter 'timetable_tray.ps1' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { $dir = $hit.DirectoryName; break }
  }
}
$fresh = $false
if (-not $dir) {
  $dir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) '내 시간표'
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $fresh = $true
}

# 2) 실행 중이면 종료
try {
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*timetable_tray.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Milliseconds 800
} catch { }

# 3) 내려받기 (기존 데이터 주소는 유지)
$wc = New-Object System.Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8; $wc.Headers.Add('Cache-Control', 'no-cache')
$stamp = [string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$oldPs1 = Join-Path $dir 'timetable_tray.ps1'
$preset = ''
if (Test-Path $oldPs1) { $m = [regex]::Match((Get-Content -Raw -Encoding UTF8 $oldPs1), "(?m)^\`$PresetDataUrl = '([^']*)'"); if ($m.Success) { $preset = $m.Groups[1].Value } }
$ver = ([string]$wc.DownloadString($Base + 'version.txt?t=' + $stamp)).Trim()
foreach ($f in $Files) {
  $bytes = $wc.DownloadData($Base + $f[0] + '?t=' + $stamp)
  $dst = Join-Path $dir $f[1]
  if ($f[1] -eq 'timetable_tray.ps1') {
    $body = [Text.Encoding]::UTF8.GetString($bytes); if ($body.Length -and [int]$body[0] -eq 0xFEFF) { $body = $body.Substring(1) }
    $errs = $null; [void][System.Management.Automation.Language.Parser]::ParseInput($body, [ref]$null, [ref]$errs)
    if ($errs -and $errs.Count) { throw '내려받은 프로그램 파일이 손상됐어요. 잠시 뒤 다시 해 주세요.' }
    if ($preset) { $body = [regex]::Replace($body, "(?m)^\`$PresetDataUrl = '[^']*'", { param($mm) '$PresetDataUrl = ''' + $preset + '''' }) }
    if (Test-Path $dst) { Copy-Item $dst ($dst + '.bak') -Force }
    [IO.File]::WriteAllText($dst, $body, (New-Object System.Text.UTF8Encoding $true))
  } else { [IO.File]::WriteAllBytes($dst, $bytes) }
}

# 4) 다시 실행
Start-Process 'wscript.exe' -ArgumentList ('"' + (Join-Path $dir '내 시간표 실행.vbs') + '"')
if ($fresh) { Msg ('내 시간표 v' + $ver + '를 설치했어요.' + "`r`n" + '폴더: ' + $dir + "`r`n`r`n" + '잠시 뒤 설정 창이 뜨면 학교 메일로 받은 개인 코드를 넣어 주세요.') }
else { Msg ('내 시간표를 v' + $ver + '로 업데이트했어요.' + "`r`n" + '폴더: ' + $dir + "`r`n`r`n" + '개인 코드와 설정은 그대로예요. 작업 표시줄 아이콘을 확인해 주세요.') }
} catch { Msg ('업데이트하지 못했어요: ' + $_.Exception.Message + "`r`n`r`n" + '잠시 뒤 다시 해 보시고, 계속 안 되면 수업계에 알려 주세요.') 'Warning'; exit 1 }
