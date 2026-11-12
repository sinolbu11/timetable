# 내 시간표 (트레이 앱) v1.7
param([string]$Launcher = '')   # 내 시간표.exe 로 실행하면 exe 위치가 들어와요 (자동 실행 등록용)
# ─────────────────────────────────────────────────────────────
# [수업계 선생님] 나눠 주기 전에 아래 줄에 PC 앱용 배포 주소를 넣어 두면,
# 선생님들은 처음 실행할 때 메일로 받은 개인 코드만 넣으면 돼요.
$PresetDataUrl = 'https://script.google.com/a/macros/simin.hs.kr/s/AKfycbwfjmnh56py7G_Bs-1wSv_Bf6CPQLYwP5QMcRwXevhIvBkv8YDeuYQbCztsrGoAI2MV/exec'
# 자동 업데이트: 아래 주소의 version.txt 가 더 높으면 timetable_tray.ps1 을 내려받아 바꿔요. (설정에서 끌 수 있음)
$AppVersion = '1.7'
$UpdateBase = 'https://sinolbu11.github.io/timetable/pc/'
$ScriptPath = $PSCommandPath
# ─────────────────────────────────────────────────────────────
# 작업 표시줄 알림 영역에 상주하면서 학교 시간표 시트에서 내 시간표와 변동만 읽어 옵니다.
# 설정은 %APPDATA%\SchoolTimetable\tray.json 에만 저장되고, 개인 코드는 Windows 계정으로 암호화됩니다.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

# ---------- 한 번만 실행 ----------
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($false, 'Local\SchoolTimetableTray', [ref]$createdNew)
if (-not $createdNew) {
  [void][System.Windows.Forms.MessageBox]::Show('내 시간표가 이미 실행 중이에요.' + "`r`n" + '작업 표시줄 오른쪽 아이콘(^ 버튼 안쪽 포함)을 확인해 주세요.', '내 시간표', 'OK', 'Information')
  return
}

try {

# ---------- 설정 ----------
$AppDir = Join-Path $env:APPDATA 'SchoolTimetable'
if (-not (Test-Path $AppDir)) { New-Item -ItemType Directory -Path $AppDir | Out-Null }
$CfgPath = Join-Path $AppDir 'tray.json'
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
$DefaultPage = 'https://script.google.com/a/macros/simin.hs.kr/s/AKfycbzh_lcGZyc-DlEl_ZestW3MBATJCIy9lLNwA3yNaF7qIIht2yIkRCnuJdokrzDdcjyaEQ/exec'

function Protect-Text([string]$Text) { if (-not $Text) { return '' }; return (ConvertFrom-SecureString (ConvertTo-SecureString $Text -AsPlainText -Force)) }
function Unprotect-Text([string]$Enc) {
  if (-not $Enc) { return '' }
  try {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR((ConvertTo-SecureString $Enc))
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
  } catch { return '' }
}
$script:Cfg = $null
if (Test-Path $CfgPath) { try { $script:Cfg = [IO.File]::ReadAllText($CfgPath, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { } }
if (-not $script:Cfg) { $script:Cfg = New-Object psobject }
foreach ($kv in @(@('DataUrl', ''), @('CodeEnc', ''), @('Name', ''), @('PageUrl', $DefaultPage), @('Pinned', $false), @('SeenSig', ''), @('MornDay', ''), @('EveDay', ''), @('AdminDay', ''), @('HomeDay', ''), @('Sound', $false), @('PreMin', 10), @('EveOn', $true), @('EveTime', '16:30'), @('Reminded', ''), @('AutoUpdate', $true), @('UpdDay', ''))) {
  if (-not ($script:Cfg.PSObject.Properties.Name -contains $kv[0])) { $script:Cfg | Add-Member -NotePropertyName $kv[0] -NotePropertyValue $kv[1] }
}
if (-not $script:Cfg.DataUrl -and $PresetDataUrl) { $script:Cfg.DataUrl = $PresetDataUrl }
$script:Code = Unprotect-Text ([string]$script:Cfg.CodeEnc)
function Save-Cfg { [IO.File]::WriteAllText($CfgPath, ($script:Cfg | ConvertTo-Json), $Utf8NoBom) }
function Is-Ready { return [bool]($script:Cfg.DataUrl -and $script:Code) }

$script:Data = $null
$script:Sig = $null
$script:Unseen = $false
$script:LastOk = $null
$script:LastErr = ''
$DayNames = @('일', '월', '화', '수', '목', '금', '토')

# ---------- 색 ----------
function C([string]$Hex) { return [System.Drawing.ColorTranslator]::FromHtml($Hex) }
$ColBg = C '#F6F6F3'; $ColSurface = C '#FFFFFF'; $ColLine = C '#E2E2DD'
$ColFg = C '#1A1C1E'; $ColMuted = C '#5F6368'; $ColFaint = C '#8A8F94'
$ColAccent = C '#E8590C'; $ColChgBg = C '#FFE7D6'; $ColChgFg = C '#9A3412'
$ColInfoBg = C '#E3EBFF'; $ColInfoFg = C '#1E3A8A'; $ColOkFg = C '#14532D'
$ColOffBg = C '#EFEFEA'; $ColBadBg = C '#FBE4E6'; $ColBadFg = C '#9F1239'; $ColToday = C '#EEF3FF'
$FontBase = New-Object System.Drawing.Font('Malgun Gothic', 9.5)
$FontSmall = New-Object System.Drawing.Font('Malgun Gothic', 8.5)
$FontTiny = New-Object System.Drawing.Font('Malgun Gothic', 7.5)
$FontBold = New-Object System.Drawing.Font('Malgun Gothic', 9.5, [System.Drawing.FontStyle]::Bold)
$FontTitle = New-Object System.Drawing.Font('Malgun Gothic', 12, [System.Drawing.FontStyle]::Bold)
$FontStrike = New-Object System.Drawing.Font('Malgun Gothic', 9.5, [System.Drawing.FontStyle]::Strikeout)

# ---------- 아이콘 (그려서 만듦) ----------
function New-TrayIcon([bool]$Badge) {
  $bmp = New-Object System.Drawing.Bitmap 32, 32
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.Clear([System.Drawing.Color]::Transparent)
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $r = 7
  $path.AddArc(2, 3, $r * 2, $r * 2, 180, 90); $path.AddArc(30 - $r * 2, 3, $r * 2, $r * 2, 270, 90)
  $path.AddArc(30 - $r * 2, 30 - $r * 2, $r * 2, $r * 2, 0, 90); $path.AddArc(2, 30 - $r * 2, $r * 2, $r * 2, 90, 90)
  $path.CloseFigure()
  $g.FillPath((New-Object System.Drawing.SolidBrush (C '#1A1C1E')), $path)
  $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 2
  $g.DrawLine($pen, 6, 11, 26, 11)
  $g.DrawLine($pen, 13, 11, 13, 26)
  $g.DrawLine($pen, 6, 18, 26, 18)
  if ($Badge) { $g.FillEllipse((New-Object System.Drawing.SolidBrush $ColAccent), 17, 17, 14, 14); $g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 2), 17, 17, 14, 14) }
  else { $g.FillEllipse((New-Object System.Drawing.SolidBrush $ColAccent), 19, 20, 6, 6) }
  $g.Dispose()
  return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}
$IconNormal = New-TrayIcon $false
$IconBadge = New-TrayIcon $true

# ---------- 데이터 ----------
function Get-Prop($Obj, [string]$Name) {
  if ($null -eq $Obj) { return $null }
  if ($Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
  return $null
}
function Get-Json([string]$Url) {
  $wc = New-Object System.Net.WebClient
  $wc.Encoding = [System.Text.Encoding]::UTF8
  $wc.Headers.Add('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) SchoolTimetableTray/1.1')
  try { $raw = $wc.DownloadString($Url) } finally { $wc.Dispose() }
  if ($raw.TrimStart().StartsWith('<')) { throw 'HTML' }
  return ($raw | ConvertFrom-Json)
}

function Get-DeployId([string]$Url) {
  $m = [regex]::Match([string]$Url, '/s/([A-Za-z0-9_-]{20,})/')
  if ($m.Success) { return $m.Groups[1].Value }
  return ''
}

# 학교 계정 배포 주소(/a/macros/학교도메인/s/...)는 로그인 없이 열면 로그인 화면으로 가요.
# 같은 배포를 /macros/s/... 로 부르면 열리는 경우가 많아서 두 가지를 차례로 시도해요.
function Get-UrlCandidates([string]$Url) {
  $u = $Url.Trim()
  $list = @()
  $plain = [regex]::Replace($u, '^https://script\.google\.com/a/macros/[^/]+/s/', 'https://script.google.com/macros/s/')
  if ($plain -ne $u) { $list += $plain }
  $list += $u
  return $list
}

function Invoke-Sheet([hashtable]$P, [string]$Url = '', [string]$Code = '', [string]$Page = '') {
  if (-not $Url) { $Url = [string]$script:Cfg.DataUrl }
  if (-not $Page) { $Page = [string]$script:Cfg.PageUrl }
  if (-not $Code) { $Code = $script:Code }
  if (-not $Url.Trim()) { throw '데이터 주소가 비어 있어요. 수업계에서 받은 PC 앱 주소를 넣어 주세요.' }
  if ((Get-DeployId $Url) -and (Get-DeployId $Url) -eq (Get-DeployId $Page)) {
    throw '데이터 주소에 학교 계정용 "내 시간표" 주소가 들어 있어요. 수업계에서 PC 앱용으로 따로 배포한 주소(액세스: 모든 사용자)를 넣어 주세요.'
  }
  $q = @('code=' + [Uri]::EscapeDataString($Code.Trim().ToUpper()))
  foreach ($k in $P.Keys) { $q += ($k + '=' + [Uri]::EscapeDataString([string]$P[$k])) }
  $lastErr = ''
  foreach ($u in (Get-UrlCandidates $Url)) {
    $sep = '?'; if ($u.Contains('?')) { $sep = '&' }
    try { $j = Get-Json ($u + $sep + ($q -join '&')) }
    catch {
      if ($_.Exception.Message -eq 'HTML') { $lastErr = 'login'; continue }
      throw
    }
    if ($j.ok) {
      if ($u -ne $Url.Trim() -and $script:Cfg.DataUrl -eq $Url) { $script:Cfg.DataUrl = $u; Save-Cfg }   # 열리는 주소로 기억
      return $j
    }
    $msg = [string]$j.error
    if ($msg -like '*읽기 키*') { throw '학교 시트가 아직 예전 버전이에요. 수업계에서 PC 앱용 배포를 "배포 관리 → 새 버전"으로 다시 배포해 주세요.' }
    throw $msg
  }
  if ($lastErr -eq 'login') {
    throw '데이터 대신 구글 로그인 화면이 와요. PC 앱용 배포의 액세스 권한이 "모든 사용자"인지 확인해 주세요. (학교 도메인만 고를 수 있다면 학교 구글 관리자가 막아 둔 거예요)'
  }
  throw '데이터를 받지 못했어요.'
}

function Get-Monday([datetime]$D) {
  $w = [int]$D.DayOfWeek
  if ($w -eq 6) { return $D.Date.AddDays(2) }
  if ($w -eq 0) { return $D.Date.AddDays(1) }
  return $D.Date.AddDays(1 - $w)
}
function Refresh([bool]$Quiet = $true) {
  if (-not (Is-Ready)) { $script:LastErr = '설정이 필요해요.'; Update-Tray; return }
  try {
    $mon = Get-Monday (Get-Date)
    $script:Data = Invoke-Sheet @{ from = $mon.ToString('yyyy-MM-dd'); days = '12' }   # 이번 주 + 다음 주
    if ($script:Data.name -and [string]$script:Data.name -ne [string]$script:Cfg.Name) { $script:Cfg.Name = [string]$script:Data.name; Save-Cfg }
    $script:LastOk = Get-Date
    $script:LastErr = ''
    $todayS = (Get-Date).ToString('yyyy-MM-dd')
    $sig = (@($script:Data.changes) | Where-Object { $_ -and [string]$_.date -ge $todayS } | ForEach-Object { '{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $_.date, $_.period, $_.cls, $_.type, $_.from, $_.to, [string](Get-Prop $_ 'row') }) -join ';'
    $shown = $false
    # 아침 첫 확인: 오늘 바뀐 수업이 있으면 하루 한 번 알림 (컴퓨터를 켠 뒤 처음)
    if ([string]$script:Cfg.MornDay -ne $todayS) {
      $script:Cfg.MornDay = $todayS; Save-Cfg
      # 오늘 바뀐 수업 + 아직 확인 안 한 변동을 아침에 한 번 창으로
      $tl = @(Get-ChangeLines | Where-Object { $_.Date -eq $todayS -or $_.NeedAck })
      if ($tl.Count) {
        $nAck = @($tl | Where-Object { $_.NeedAck }).Count
        $ttl = '오늘 바뀐 수업'; if ($nAck) { $ttl += ' · 확인 안 한 변동 ' + $nAck + '건' }
        Show-Alert $ttl '오늘 수업 전에 한 번 확인해 주세요.' $tl
        $tl | Where-Object { $_.NeedAck } | ForEach-Object { Mark-Reminded ('morn:' + $todayS + ':' + $_.Row) }
        $script:Unseen = $true; $shown = $true
      }
    }
    # 새로 생기거나 바뀐 변동 (꺼져 있는 동안 생긴 것도 포함)
    if (-not $shown -and [string]$script:Cfg.SeenSig -ne '' -and $sig -ne [string]$script:Cfg.SeenSig) {
      $k6 = { param($e) ($e.Split('|') | Select-Object -First 6) -join '|' }
      $old = @(([string]$script:Cfg.SeenSig).Split(';') | Where-Object { $_ } | ForEach-Object { & $k6 $_ })
      $new = @($sig.Split(';') | Where-Object { $_ -and $old -notcontains (& $k6 $_) })
      if ($new.Count) {
        $rows = @($new | ForEach-Object { $p = $_.Split('|'); if ($p.Count -ge 7) { [int]$p[6] } })
        $items = @(Get-ChangeLines | Where-Object { $rows -contains $_.Row })
        if (-not $items.Count) { $items = @($new | ForEach-Object { $p = $_.Split('|'); [pscustomobject]@{ Text = (Format-ChangeShort $p[0] $p[1] $p[2] $p[3] $p[5]); Row = 0; NeedAck = $false; In = ($p[5] -eq [string]$script:Cfg.Name); Warn = $false; Date = $p[0] } }) }
        Show-Alert ('새 시간표 변동 ' + $items.Count + '건') '수업계에서 시간표를 바꿨어요.' $items
        $script:Unseen = $true
      }
    }
    if ([string]$script:Cfg.SeenSig -ne $sig) { $script:Cfg.SeenSig = $sig; Save-Cfg }
    # 담임: 하루 한 번 오늘 우리 반 바뀐 수업
    $hr = [string](Get-Prop $script:Data 'homeroom')
    if ($hr -and [string]$script:Cfg.HomeDay -ne $todayS) {
      $script:Cfg.HomeDay = $todayS; Save-Cfg
      $hl = @(Get-HomeLines $todayS)
      if ($hl.Count) {
        if ($shown) { Start-Sleep -Milliseconds 300 }
        Show-Balloon ('오늘 우리 반 ' + $hr + ' 바뀐 수업 ' + $hl.Count + '건') (($hl | Select-Object -First 3) -join "`r`n")
        $shown = $true
      }
    }
    # 관리자: 하루 한 번 오늘 학교 전체 변동 요약
    $adm = Get-Admin
    if ($adm -and [string]$script:Cfg.AdminDay -ne $todayS) {
      $script:Cfg.AdminDay = $todayS; Save-Cfg
      if ([int]$adm.todayCount -gt 0 -and -not $shown) {
        $al = @(@($adm.today) | Select-Object -First 3 | ForEach-Object { Format-AdminItem $_ })
        Show-Balloon ('오늘 학교 변동 ' + $adm.todayCount + '건 · 미확인 ' + $adm.unacked + '건') ($al -join "`r`n")
      }
    }
    $script:Sig = $sig
  } catch {
    $script:LastErr = $_.Exception.Message
    if ($_.Exception.ToString() -match 'WebException|원격 이름|remote name') { $script:LastErr = '인터넷이나 학교 방화벽 때문에 연결하지 못했어요.' }
    if (-not $Quiet) { [void][System.Windows.Forms.MessageBox]::Show($script:LastErr, '내 시간표', 'OK', 'Warning') }
  }
  Update-Tray
  if ($popup.Visible) { Render-Popup }
}

# ---------- 오늘 수업 계산 ----------
function Get-TodayRows {
  $rows = @()
  if (-not $script:Data) { return $rows }
  $today = (Get-Date).ToString('yyyy-MM-dd')
  $day = @($script:Data.days) | Where-Object { $_.date -eq $today } | Select-Object -First 1
  if (-not $day) { return $rows }
  $mine = Get-Prop (Get-Prop $day 'slots') ([string]$script:Cfg.Name)
  $per = [int]$script:Data.periods; if ($per -lt 1) { $per = 7 }
  for ($p = 1; $p -le $per; $p++) {
    $entries = @()
    $raw = Get-Prop $mine ([string]$p)
    if ($null -ne $raw) { $entries = @($raw); if ($entries.Count -gt 0 -and -not ($entries[0] -is [array])) { $entries = @(, $entries) } }
    $live = @($entries | Where-Object { [string]$_[3] -ne 'removed' })
    $gone = @($entries | Where-Object { [string]$_[3] -eq 'removed' })
    $bad = [bool](Get-Prop (Get-Prop $day 'conflicts') ([string]$p))
    $kind = 'free'; $text = '공강'
    if ($live.Count) {
      $text = ($live | ForEach-Object { $t = [string]$_[0] + '  ' + [string]$_[1]; if ([string]$_[2]) { $t += ' · ' + [string]$_[2] }; $t }) -join ', '
      $kind = 'normal'
      if ($bad) { $kind = 'bad' }
      elseif (@($live | Where-Object { [string]$_[3] -eq 'added' }).Count) { $kind = 'added'; $text = '[' + [string](@($live | Where-Object { [string]$_[3] -eq 'added' })[0][4]) + '] ' + $text }
    } elseif ($gone.Count) {
      $kind = 'removed'; $text = ($gone | ForEach-Object { [string]$_[0] + '  ' + [string]$_[1] }) -join ', '
    }
    $short = ''; $cls1 = ''
    if ($live.Count) { $short = [string]$live[0][0] + ' ' + [string]$live[0][1]; $cls1 = [string]$live[0][0] }
    $rows += [pscustomobject]@{ P = $p; Kind = $kind; Text = $text; Short = $short; Cls = $cls1 }
  }
  return $rows
}

function Get-ChangeLines {
  $lines = @()
  if (-not $script:Data) { return $lines }
  $me = [string]$script:Cfg.Name
  $todayS = (Get-Date).ToString('yyyy-MM-dd')
  $mine = Get-Prop $script:Data 'mine'
  if ($null -ne $mine) {
    # 서버가 선생님 기준으로 묶어 준 문장 (내 수업이 옮겨져요 / 보강 들어가요 / 수업이 빠져요)
    foreach ($x in @(@($mine) | Where-Object { $_ -and ([string]$_.date -ge $todayS -or [string](Get-Prop $_ 'oldDate') -ge $todayS) })) {
      $k = [string]$x.kind
      $mark = '[빠짐]'; if ($k -eq 'move') { $mark = '[이동]' } elseif ($k -eq 'in') { $mark = '[들어감]' }
      $when = [string]$x.now
      if ($k -eq 'move') { $when = [string]$x.old + ' → ' + [string]$x.now } elseif ($k -eq 'out') { $when = [string]$x.old }
      $t = ([string]$x.title) -replace '^[^·]*·\s*', ''
      $warn = [bool](Get-Prop $x 'warn'); $acked = Get-Prop $x 'acked'; $need = [bool](Get-Prop $x 'needAck')
      $lines += [pscustomobject]@{ In = ($k -ne 'out'); Warn = $warn; Row = [int](Get-Prop $x 'row'); NeedAck = ($need -and $acked -eq $false -and -not $warn); Acked = ($need -and $acked -eq $true);
        Date = [string]$x.date; Period = [int]$x.period; Cls = [string]$x.cls;
        Text = ('{0} {1}  {2} · {3}' -f $mark, $when, $t, [string]$x.note) }
    }
    return $lines
  }
  foreach ($c in @(@($script:Data.changes) | Where-Object { $_ -and [string]$_.date -ge $todayS } | Sort-Object date, { [int]$_.period })) {
    $dt = [datetime]::ParseExact([string]$c.date, 'yyyy-MM-dd', $null)
    $mineIn = ([string]$c.to -eq $me)
    $what = ''
    if ($mineIn) { $what = '들어가요 (' + [string]$c.type + ')' } else { $what = '빠져요 → ' + [string]$c.to + ' (' + [string]$c.type + ')' }
    $acked = Get-Prop $c 'acked'
    $lines += [pscustomobject]@{ In = $mineIn; Warn = ([string]$c.status -like '⚠*'); Row = [int](Get-Prop $c 'row'); NeedAck = ($mineIn -and $acked -eq $false -and -not ([string]$c.status -like '⚠*')); Acked = ($acked -eq $true);
      Date = [string]$c.date; Period = [int]$c.period; Cls = [string]$c.cls;
      Text = ('{0}({1}) {2}교시 {3}  {4}' -f $dt.ToString('M/d'), $DayNames[[int]$dt.DayOfWeek], $c.period, $c.cls, $what) }
  }
  return $lines
}

# ---------- 지금 교시 / 다음 수업 ----------
function To-Min([string]$Hm) { $a = $Hm.Split(':'); return [int]$a[0] * 60 + [int]$a[1] }
function Get-NowNext {
  # 반환: @{ Now = '지금 2교시 · 3-5 물리학Ⅱ (10:30까지)'; Next = '다음 4교시 3-6 · 11:40 (25분 뒤)'; Short = '다음: 4교시 3-6 11:40'; P = 현재 교시 }
  $res = @{ Now = ''; Next = ''; Short = ''; P = 0 }
  if (-not $script:Data) { return $res }
  $bells = @(Get-Prop $script:Data 'bells') | Where-Object { $_ }
  if (-not $bells.Count) { return $res }
  $rows = @(Get-TodayRows)
  if (-not $rows.Count) { return $res }
  $n = Get-Date; $m = $n.Hour * 60 + $n.Minute
  foreach ($b in $bells) {
    if ($m -ge (To-Min $b.s) -and $m -lt (To-Min $b.e)) {
      $res.P = [int]$b.p
      $r = $rows | Where-Object { $_.P -eq [int]$b.p } | Select-Object -First 1
      $what = '공강'; if ($r -and $r.Kind -ne 'free' -and $r.Kind -ne 'removed') { $what = $r.Short }
      $res.Now = '지금 ' + $b.p + '교시 · ' + $what + ' (' + $b.e + '까지)'
    }
  }
  foreach ($b in $bells) {
    if ((To-Min $b.s) -le $m) { continue }
    $r = $rows | Where-Object { $_.P -eq [int]$b.p -and $_.Kind -ne 'free' -and $_.Kind -ne 'removed' } | Select-Object -First 1
    if (-not $r) { continue }
    $left = (To-Min $b.s) - $m
    $ls = if ($left -ge 60) { [string][Math]::Floor($left / 60) + '시간 ' + ($left % 60) + '분' } else { [string]$left + '분' }
    $res.Next = '다음 수업 ' + $b.p + '교시 ' + $r.Short + ' · ' + $b.s + ' (' + $ls + ' 뒤)'
    $res.Short = '다음: ' + $b.p + '교시 ' + $r.Cls + ' ' + $b.s
    break
  }
  if (-not $res.Now -and -not $res.Next) {
    $last = $bells[$bells.Count - 1]
    if ($m -ge (To-Min $last.e)) { $res.Next = '오늘 수업이 모두 끝났어요.' }
  }
  return $res
}
function Get-BellText([int]$P) {
  if (-not $script:Data) { return '' }
  $b = @(Get-Prop $script:Data 'bells') | Where-Object { $_ -and [int]$_.p -eq $P } | Select-Object -First 1
  if ($b) { return [string]$b.s } else { return '' }
}

# ---------- 알림 문구 ----------
function Show-Balloon([string]$Title, [string]$Text) {
  if (-not $Text) { $Text = ' ' }
  if ($Text.Length -gt 250) { $Text = $Text.Substring(0, 250) }
  $tray.BalloonTipTitle = $Title; $tray.BalloonTipText = $Text; $tray.ShowBalloonTip(10000)
}
function Format-ChangeShort([string]$Date, $Period, [string]$Cls, [string]$Type, [string]$To) {
  $dt = [datetime]::ParseExact($Date, 'yyyy-MM-dd', $null)
  $role = if ($To -eq [string]$script:Cfg.Name) { '들어가요' } else { '빠져요' }
  return ('{0}({1}) {2}교시 {3} {4} · {5}' -f $dt.ToString('M/d'), $DayNames[[int]$dt.DayOfWeek], $Period, $Cls, $Type, $role)
}
function Get-MyChangesOn([string]$Ymd) {
  if (-not $script:Data) { return @() }
  return @(@($script:Data.changes) | Where-Object { $_ -and [string]$_.date -eq $Ymd -and -not ([string]$_.status -like '⚠*') } | Sort-Object { [int]$_.period } |
    ForEach-Object { Format-ChangeShort ([string]$_.date) $_.period ([string]$_.cls) ([string]$_.type) ([string]$_.to) })
}
# 담임 반 바뀐 수업 (그날)
function Get-HomeLines([string]$Ymd) {
  if (-not $script:Data) { return @() }
  $hc = @(Get-Prop $script:Data 'homeChanges') | Where-Object { $_ -and [string]$_.date -eq $Ymd } | Sort-Object { [int]$_.period }
  return @($hc | ForEach-Object {
    $subj = if ($_.was -and $_.now -and [string]$_.was -ne [string]$_.now) { [string]$_.was + ' → ' + [string]$_.now } else { [string]$(if ($_.now) { $_.now } else { $_.was }) }
    $who = ''
    if ($_.to) { $who = $(if ($_.from -and [string]$_.from -ne [string]$_.to) { [string]$_.from + '→' } else { '' }) + [string]$_.to }
    [string]$_.period + '교시 ' + $subj + $(if ($who) { ' · ' + $who } else { '' }) + ' (' + [string]$_.type + ')'
  })
}
function Get-NextSchoolDay {
  $d = (Get-Date).Date.AddDays(1)
  while ([int]$d.DayOfWeek -eq 0 -or [int]$d.DayOfWeek -eq 6) { $d = $d.AddDays(1) }
  return $d
}
function Check-Evening {
  # 평일, 설정한 시각 이후 하루 한 번: 다음 수업일 바뀐 수업 미리 알림 (설정에서 끌 수 있음)
  if (-not [bool]$script:Cfg.EveOn) { return }
  $n = Get-Date
  $et = 990; try { $et = To-Min ([string]$script:Cfg.EveTime) } catch { }
  if ([int]$n.DayOfWeek -eq 0 -or [int]$n.DayOfWeek -eq 6 -or ($n.Hour * 60 + $n.Minute) -lt $et) { return }
  $todayS = $n.ToString('yyyy-MM-dd')
  if ([string]$script:Cfg.EveDay -eq $todayS -or -not $script:Data -or $script:LastErr) { return }
  $script:Cfg.EveDay = $todayS; Save-Cfg
  $nd = Get-NextSchoolDay
  $tl = @(Get-MyChangesOn $nd.ToString('yyyy-MM-dd'))
  if ($tl.Count) {
    $label = if ($nd.Date -eq $n.Date.AddDays(1)) { '내일' } else { $DayNames[[int]$nd.DayOfWeek] + '요일' }
    $ndS = $nd.ToString('yyyy-MM-dd')
    $items = @(Get-ChangeLines | Where-Object { $_.Date -eq $ndS })
    if (-not $items.Count) { $items = @($tl | ForEach-Object { [pscustomobject]@{ Text = $_; Row = 0; NeedAck = $false; In = $true; Warn = $false; Date = $ndS } }) }
    Show-Alert ($label + '(' + $nd.ToString('M/d') + ') 바뀐 수업 ' + $items.Count + '건') '퇴근 전에 미리 확인해 두세요.' $items
    $script:Unseen = $true; Update-Tray
  }
}

# ---------- 재알림 / 수업 전 알림 (1분마다 확인) ----------
function Was-Reminded([string]$Key) { return ((([string]$script:Cfg.Reminded).Split(';')) -contains $Key) }
function Mark-Reminded([string]$Key) {
  $all = @(([string]$script:Cfg.Reminded).Split(';') | Where-Object { $_ })
  if ($all -contains $Key) { return }
  $all += $Key
  # 지난 날짜 것은 지움 (키 형식: 종류:날짜:행)
  $td = (Get-Date).ToString('yyyy-MM-dd')
  $all = @($all | Where-Object { $p = $_.Split(':'); $p.Count -lt 2 -or $p[1] -ge $td })
  $script:Cfg.Reminded = ($all -join ';'); Save-Cfg
}
function Check-Reminders {
  if (-not $script:Data -or $script:LastErr -or $alert.Visible) { return }
  $n = Get-Date; $m = $n.Hour * 60 + $n.Minute; $todayS = $n.ToString('yyyy-MM-dd')
  $lines = @(Get-ChangeLines | Where-Object { $_.Date -eq $todayS -and $_.Period -gt 0 })
  if (-not $lines.Count) { return }
  # ① 확인 안 한 변동: 그 수업 1시간 전에 한 번 더
  $again = @()
  foreach ($ln in ($lines | Where-Object { $_.NeedAck })) {
    $bs = Get-BellText $ln.Period; if (-not $bs) { continue }
    $st = To-Min $bs; $key = 'pre:' + $todayS + ':' + $ln.Row
    if ($m -ge ($st - 60) -and $m -lt $st -and -not (Was-Reminded $key)) { $again += $ln; Mark-Reminded $key }
  }
  if ($again.Count) { Show-Alert ('아직 확인하지 않은 변동 ' + $again.Count + '건') '1시간 안에 시작하는 수업이에요. [확인했어요]를 눌러 주세요.' $again; return }
  # ② 수업 전 미리 알림 (설정: 몇 분 전, 0이면 안 함) — 내가 들어가는 바뀐 수업만
  $pm = 0; try { $pm = [int]$script:Cfg.PreMin } catch { }
  if ($pm -le 0) { return }
  $soon = @()
  foreach ($ln in ($lines | Where-Object { $_.In -and -not $_.Warn })) {
    $bs = Get-BellText $ln.Period; if (-not $bs) { continue }
    $st = To-Min $bs; $key = 'soon:' + $todayS + ':' + $ln.Row + ':' + $ln.Period
    if ($m -ge ($st - $pm) -and $m -lt $st -and -not (Was-Reminded $key)) { $soon += $ln; Mark-Reminded $key }
  }
  if ($soon.Count) { Show-Alert ('곧 바뀐 수업이에요 · ' + $soon[0].Period + '교시 ' + (Get-BellText $soon[0].Period)) ('수업 ' + $pm + '분 전이에요.') $soon }
}
function Get-Admin { if ($script:Data) { return (Get-Prop $script:Data 'admin') } else { return $null } }
function Has-MyLessons {
  if (-not $script:Data) { return $false }
  $me = [string]$script:Cfg.Name
  foreach ($d in @($script:Data.days)) { if ($d -and (Get-Prop (Get-Prop $d 'slots') $me)) { return $true } }
  return $false
}
function Format-AdminItem($it) {
  $t = [string]$it.period + '교시 ' + [string]$it.cls + ' ' + [string]$it.type
  $desc = [string]$it.desc
  $m = [regex]::Match($desc, '([^\s/]+→[^\s/(]+)')
  if ($m.Success) { $t += ' · ' + $m.Groups[1].Value }
  $miss = @($it.miss) | Where-Object { $_ }
  if ($it.warn) { $t += '  ⚠ 확인 필요' } elseif ($miss.Count) { $t += '  (미확인: ' + ($miss -join ', ') + ')' }
  return $t
}

function Has-PendingAck {
  if (-not $script:Data) { return $false }
  $todayS = (Get-Date).ToString('yyyy-MM-dd'); $me = [string]$script:Cfg.Name
  return [bool](@($script:Data.changes) | Where-Object { $_ -and [string]$_.to -eq $me -and [string]$_.date -ge $todayS -and (Get-Prop $_ 'acked') -eq $false -and -not ([string]$_.status -like '⚠*') } | Select-Object -First 1)
}

function Update-Tray {
  $tray.Icon = $(if ($script:Unseen -or (Has-PendingAck)) { $IconBadge } else { $IconNormal })
  $tip = '내 시간표'
  if (-not (Is-Ready)) { $tip += ' · 설정이 필요해요' }
  elseif ($script:LastErr) { $tip += ' · 연결 안 됨' }
  elseif ($script:Data) {
    $n = @($script:Data.changes | Where-Object { $_ }).Count
    $nn = Get-NowNext
    $adm = Get-Admin
    if ($nn.Short) { $tip = $nn.Short + ' · 변동 ' + $n + '건' }
    elseif ($adm -and -not (Has-MyLessons)) { $tip = '학교 변동 오늘 ' + $adm.todayCount + '건 · 미확인 ' + $adm.unacked + '건' }
    else { $tip += ' · 이번 주 변동 ' + $n + '건' }
  }
  if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
  $tray.Text = $tip
}

# ---------- 작은 창 ----------
$popup = New-Object System.Windows.Forms.Form
$popup.FormBorderStyle = 'None'
$popup.ShowInTaskbar = $false
$popup.TopMost = $true
$popup.StartPosition = 'Manual'
$popup.BackColor = $ColLine
$popup.Padding = New-Object System.Windows.Forms.Padding(1)
$popup.Size = New-Object System.Drawing.Size(380, 560)
$popup.Font = $FontBase
$popup.KeyPreview = $true

$inner = New-Object System.Windows.Forms.Panel
$inner.Dock = 'Fill'
$inner.BackColor = $ColBg
$inner.AutoScroll = $true
$popup.Controls.Add($inner)

function Add-Label([System.Windows.Forms.Control]$Parent, [string]$Text, $Font, $Fore, [int]$X, [int]$Y, [int]$W, $Back = $null) {
  $l = New-Object System.Windows.Forms.Label
  $l.Text = $Text; $l.Font = $Font; $l.ForeColor = $Fore
  $l.Location = New-Object System.Drawing.Point($X, $Y)
  $l.MaximumSize = New-Object System.Drawing.Size($W, 0)
  $l.AutoSize = $true
  if ($Back) { $l.BackColor = $Back } else { $l.BackColor = [System.Drawing.Color]::Transparent }
  $Parent.Controls.Add($l)
  return $l
}
function Add-Btn([System.Windows.Forms.Control]$Parent, [string]$Text, [int]$X, [int]$Y, [int]$W, [scriptblock]$OnClick) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $Text; $b.Location = New-Object System.Drawing.Point($X, $Y); $b.Size = New-Object System.Drawing.Size($W, 30)
  $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderColor = $ColLine; $b.BackColor = $ColSurface; $b.Font = $FontBase
  $b.Add_Click($OnClick)
  $Parent.Controls.Add($b)
  return $b
}

function Send-Ack([int]$Row) {
  try {
    $r = Invoke-Sheet @{ ack = [string]$Row }
    foreach ($c in @($script:Data.changes)) { if ($c -and [int](Get-Prop $c 'row') -eq $Row) { $c.acked = $true } }
    $mine = Get-Prop $script:Data 'mine'
    if ($null -ne $mine) { foreach ($x in @($mine)) { if ($x -and [int](Get-Prop $x 'row') -eq $Row -and (Get-Prop $x 'needAck')) { $x.acked = $true } } }
    Update-Tray
  } catch { [void][System.Windows.Forms.MessageBox]::Show('확인을 보내지 못했어요: ' + $_.Exception.Message, '내 시간표', 'OK', 'Warning') }
  if ($popup.Visible) { Render-Popup }
}

function Render-Popup {
  $inner.SuspendLayout()
  foreach ($c in @($inner.Controls)) { $c.Dispose() }
  $inner.Controls.Clear()
  $W = 340; $x = 16; $y = 12
  $now = Get-Date
  if (Is-Ready) { $title = [string]$script:Cfg.Name + ' 선생님' } else { $title = '내 시간표' }
  [void](Add-Label $inner $title $FontTitle $ColFg $x $y $W); $y += 28
  $sub = $now.ToString('M/d') + '(' + $DayNames[[int]$now.DayOfWeek] + ')'
  if ($script:LastOk) { $sub += ' · 마지막 확인 ' + $script:LastOk.ToString('HH:mm') }
  [void](Add-Label $inner $sub $FontSmall $ColMuted $x $y $W); $y += 24

  if (-not (Is-Ready)) {
    [void](Add-Label $inner '처음 한 번 설정이 필요해요. 학교 메일로 받은 개인 코드를 넣어 주세요.' $FontBase $ColFg $x $y $W); $y += 50
    [void](Add-Btn $inner '설정 열기' $x $y 120 { Show-Settings }); $y += 40
  } else {
    if ($script:LastErr) {
      $e = Add-Label $inner ('⚠ ' + $script:LastErr) $FontSmall $ColBadFg $x $y $W $ColBadBg
      $e.Padding = New-Object System.Windows.Forms.Padding(6); $y += $e.PreferredHeight + 8
    }
    # 관리자: 학교 전체 요약
    $adm = Get-Admin
    $mine = Has-MyLessons
    if ($adm) {
      [void](Add-Label $inner '학교 전체 · 오늘' $FontBold $ColFg $x $y $W); $y += 22
      $sumT = '오늘 ' + $adm.todayCount + '건 · 이번 주 ' + $adm.week + '건 · 선생님 미확인 ' + $adm.unacked + '건'
      if ([int]$adm.warn -gt 0) { $sumT += ' · 확인 필요 ' + $adm.warn + '건' }
      if ([int]$adm.neisTodo -gt 0) { $sumT += ' · 나이스 미반영 ' + $adm.neisTodo + '건' }
      $sl = Add-Label $inner $sumT $FontSmall $ColInfoFg $x $y $W $ColInfoBg
      $sl.Padding = New-Object System.Windows.Forms.Padding(8, 5, 8, 5); $sl.MinimumSize = New-Object System.Drawing.Size($W, 0)
      $y += $sl.PreferredHeight + 6
      $items = @(@($adm.today) | Where-Object { $_ })
      if (-not $items.Count) { [void](Add-Label $inner '오늘은 학교 전체에 바뀐 수업이 없어요.' $FontBase $ColMuted $x $y $W); $y += 22 }
      foreach ($it in ($items | Select-Object -First 8)) {
        $fore = $ColFg; if ($it.warn) { $fore = $ColBadFg } elseif (@($it.miss | Where-Object { $_ }).Count) { $fore = $ColChgFg }
        $l = Add-Label $inner ('• ' + (Format-AdminItem $it)) $FontBase $fore $x $y $W
        $y += [Math]::Max(20, $l.PreferredHeight + 2)
      }
      if ($items.Count -gt 8) { [void](Add-Label $inner ('… 외 ' + ($items.Count - 8) + '건') $FontSmall $ColMuted $x $y $W); $y += 20 }
      [void](Add-Btn $inner '학교 전체 보기' $x ($y + 2) 130 { Open-Page 'school' }); $y += 42
    }
    if ($adm -and -not $mine) {
      # 수업이 없는 관리자(교장·교감)는 학교 요약만
    } else {
    # 오늘 시정 변경 (단축수업 등)
    $tdS = (Get-Date).ToString('yyyy-MM-dd')
    $tdDay = @($script:Data.days) | Where-Object { $_ -and $_.date -eq $tdS } | Select-Object -First 1
    $bn = [string](Get-Prop $tdDay 'bellNote')
    if ($bn) { [void](Add-Label $inner ('⏰ 오늘 시정 변경: ' + $bn) $FontBold $ColChgFg $x $y $W); $y += 24 }
    # 지금 / 다음 수업
    $nn = Get-NowNext
    $nt = @($nn.Now, $nn.Next) | Where-Object { $_ }
    if ($nt.Count) {
      $nb = Add-Label $inner ($nt -join "`r`n") $FontBase $ColInfoFg $x $y $W $ColInfoBg
      $nb.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6); $nb.MinimumSize = New-Object System.Drawing.Size($W, 0)
      $y += $nb.PreferredHeight + 10
    }
    # 담임: 오늘 우리 반
    $hr = [string](Get-Prop $script:Data 'homeroom')
    if ($hr) {
      $hl = @(Get-HomeLines ((Get-Date).ToString('yyyy-MM-dd')))
      [void](Add-Label $inner ('오늘 우리 반 ' + $hr + $(if ($hl.Count) { ' · 바뀐 수업 ' + $hl.Count + '건' } else { '' })) $FontBold $ColFg $x $y $W); $y += 22
      if (-not $hl.Count) { [void](Add-Label $inner '오늘 우리 반 시간표는 그대로예요.' $FontSmall $ColMuted $x $y $W); $y += 22 }
      foreach ($l in $hl) { $lb = Add-Label $inner ('• ' + $l) $FontBase $ColChgFg $x $y $W; $y += [Math]::Max(20, $lb.PreferredHeight + 2) }
      $y += 8
    }
    # 오늘 내 수업
    [void](Add-Label $inner '오늘 내 수업' $FontBold $ColFg $x $y $W); $y += 22
    $rows = Get-TodayRows
    if (-not $rows.Count) {
      $msg = '오늘은 수업 정보가 없어요.'
      if ([int]$now.DayOfWeek -eq 0 -or [int]$now.DayOfWeek -eq 6) { $msg = '주말이에요. 이번 주 변동은 아래에서 확인하세요.' }
      [void](Add-Label $inner $msg $FontBase $ColMuted $x $y $W); $y += 26
    }
    foreach ($r in $rows) {
      $panel = New-Object System.Windows.Forms.Panel
      $panel.Location = New-Object System.Drawing.Point($x, $y); $panel.Size = New-Object System.Drawing.Size($W, 28)
      $back = $ColSurface; $fore = $ColFg; $font = $FontBase
      switch ($r.Kind) {
        'added' { $back = $ColChgBg; $fore = $ColChgFg; $font = $FontBold }
        'bad' { $back = $ColBadBg; $fore = $ColBadFg; $font = $FontBold }
        'removed' { $back = $ColOffBg; $fore = $ColFaint; $font = $FontStrike }
        'free' { $back = $ColBg; $fore = $ColFaint }
      }
      if ($nn.P -eq $r.P) { $panel.BorderStyle = 'FixedSingle'; if ($r.Kind -eq 'normal' -or $r.Kind -eq 'free') { $back = $ColInfoBg } }
      $panel.BackColor = $back
      $bt = Get-BellText $r.P
      [void](Add-Label $panel ([string]$r.P + '교시') $FontBold $ColMuted 8 6 50)
      if ($bt) { [void](Add-Label $panel $bt $FontTiny $ColFaint ($W - 44) 7 40) }
      $t = $r.Text; if ($r.Kind -eq 'removed') { $t = $t + '  (빠짐)' }
      [void](Add-Label $panel $t $font $fore 62 6 ($W - 112))
      $inner.Controls.Add($panel)
      $y += 31
    }
    $y += 8
    # 이번 주 변동
    $lines = Get-ChangeLines
    [void](Add-Label $inner ('나와 관련된 변동 (이번 주·다음 주) ' + $lines.Count + '건') $FontBold $ColFg $x $y $W); $y += 22
    if (-not $lines.Count) { [void](Add-Label $inner '없어요.' $FontBase $ColMuted $x $y $W); $y += 22 }
    foreach ($ln in $lines) {
      $fore = $ColFg; if ($ln.In) { $fore = $ColChgFg }; if ($ln.Warn) { $fore = $ColBadFg }
      $l = Add-Label $inner ('• ' + $ln.Text) $FontBase $fore $x $y ($W - 78)
      if ($ln.NeedAck) {
        $lk = New-Object System.Windows.Forms.LinkLabel
        $lk.Text = '확인했어요'; $lk.Font = $FontSmall; $lk.AutoSize = $true; $lk.Tag = $ln.Row
        $lk.Location = New-Object System.Drawing.Point(($x + $W - 70), ($y + 1)); $lk.LinkColor = $ColAccent
        $lk.Add_LinkClicked({ Send-Ack ([int]$this.Tag) })
        $inner.Controls.Add($lk)
      } elseif ($ln.Acked) {
        [void](Add-Label $inner '✓ 확인함' $FontSmall $ColOkFg ($x + $W - 62) ($y + 1) 70)
      }
      $y += [Math]::Max(20, $l.PreferredHeight + 2)
    }
    $y += 8
    }
  }
  # 아래 버튼
  [void](Add-Btn $inner '주간 시간표' $x $y 110 { Open-Page '' })
  [void](Add-Btn $inner '새로고침' ($x + 116) $y 90 { Refresh $false })
  [void](Add-Btn $inner '설정' ($x + 212) $y 60 { Show-Settings })
  $y += 40
  $pin = New-Object System.Windows.Forms.CheckBox
  $pin.Text = '창 고정 (다른 곳을 눌러도 닫히지 않음)'; $pin.Font = $FontSmall; $pin.ForeColor = $ColMuted
  $pin.Location = New-Object System.Drawing.Point($x, $y); $pin.AutoSize = $true; $pin.Checked = [bool]$script:Cfg.Pinned
  $pin.Add_CheckedChanged({ $script:Cfg.Pinned = $this.Checked; Save-Cfg })
  $inner.Controls.Add($pin)
  $y += 30
  $inner.ResumeLayout()
  $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $h = [Math]::Min($y + 8, $wa.Height - 20)
  $popup.Size = New-Object System.Drawing.Size(380, $h)
  $popup.Location = New-Object System.Drawing.Point(($wa.Right - $popup.Width - 12), ($wa.Bottom - $popup.Height - 12))
}

function Show-Popup {
  $script:Unseen = $false
  Update-Tray
  Render-Popup
  $popup.Show()
  $popup.Activate()
}
$script:HiddenAt = [datetime]::MinValue
$popup.Add_Deactivate({ if (-not $script:Cfg.Pinned -and -not $script:InDialog) { $popup.Hide(); $script:HiddenAt = Get-Date } })
$popup.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $popup.Hide() } })

function Open-Page([string]$Tab = '') {
  $u = [string]$script:Cfg.PageUrl
  if (-not $u) { return }
  if ($Tab) { $u = $u.Split('?')[0] + '?tab=' + $Tab }
  try { Start-Process 'msedge.exe' -ArgumentList ('--app="' + $u + '"'), '--window-size=1100,860' } catch { Start-Process $u }
}

# ---------- 자동 업데이트 ----------
function Check-Update([bool]$Force = $false) {
  if (-not $Force -and -not [bool]$script:Cfg.AutoUpdate) { return $false }
  if (-not $UpdateBase -or -not $ScriptPath) { return $false }
  $todayS = (Get-Date).ToString('yyyy-MM-dd')
  if (-not $Force -and [string]$script:Cfg.UpdDay -eq $todayS) { return $false }
  $script:Cfg.UpdDay = $todayS; Save-Cfg
  try {
    $wc = New-Object System.Net.WebClient
    $wc.Encoding = [Text.Encoding]::UTF8
    $wc.Headers.Add('Cache-Control', 'no-cache')
    $stamp = [string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $remote = ([string]$wc.DownloadString($UpdateBase + 'version.txt?t=' + $stamp)).Trim()
    if (-not ($remote -match '^\d+(\.\d+)+$')) { return $false }
    if ([version]$remote -le [version]$AppVersion) { return $false }
    $body = [string]$wc.DownloadString($UpdateBase + 'timetable_tray.ps1?t=' + $stamp)
    $verLine = "AppVersion = '" + $remote + "'"
    if ($body.Length -lt 20000 -or -not $body.Contains($verLine)) { return $false }
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($body, [ref]$null, [ref]$errs)
    if ($errs -and $errs.Count) { return $false }
    # 수업계가 넣어 둔 데이터 주소는 내 파일 것을 그대로 유지
    if ($PresetDataUrl) {
      $pat = '(?m)^\$PresetDataUrl = ''[^'']*'''
      $rpl = '$PresetDataUrl = ''' + $PresetDataUrl + ''''
      $body = [regex]::Replace($body, $pat, { param($m) $rpl })
    }
    $bak = $ScriptPath + '.bak'
    Copy-Item $ScriptPath $bak -Force
    [IO.File]::WriteAllText($ScriptPath, $body, (New-Object System.Text.UTF8Encoding $true))
    # 다시 시작
    $dir = Split-Path $ScriptPath
    $vbs = Join-Path $dir '내 시간표 실행.vbs'
    $tray.Visible = $false
    try { $mutex.ReleaseMutex(); $mutex.Dispose() } catch { }
    if (Test-Path $vbs) { Start-Process 'wscript.exe' -ArgumentList ('"' + $vbs + '"') }
    else { Start-Process 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $ScriptPath + '"') -WindowStyle Hidden }
    Exit-App
    return $true
  } catch { return $false }
}
function Exit-App { [System.Windows.Forms.Application]::Exit() }

# ---------- 사라지지 않는 알림 창 ----------
$alert = New-Object System.Windows.Forms.Form
$alert.Text = '내 시간표 알림'; $alert.Font = $FontBase
$alert.FormBorderStyle = 'FixedToolWindow'; $alert.StartPosition = 'Manual'; $alert.TopMost = $true; $alert.ShowInTaskbar = $true
$alert.BackColor = $ColBg; $alert.MaximizeBox = $false; $alert.MinimizeBox = $false
$alert.Size = New-Object System.Drawing.Size(440, 300)
$alertInner = New-Object System.Windows.Forms.Panel; $alertInner.Dock = 'Fill'; $alertInner.AutoScroll = $true; $alertInner.BackColor = $ColBg
$alert.Controls.Add($alertInner)
$script:AlertItems = @(); $script:AlertTitle = ''; $script:AlertSub = ''
$alert.Add_FormClosing({ if ($_.CloseReason -eq 'UserClosing') { $_.Cancel = $true; $alert.Hide() } })
$alert.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $alert.Hide() } })
$alert.KeyPreview = $true

function Render-Alert {
  $alertInner.SuspendLayout()
  foreach ($c in @($alertInner.Controls)) { $c.Dispose() }
  $alertInner.Controls.Clear()
  $W = 392; $x = 16; $y = 12
  $items = @($script:AlertItems)
  $need = @($items | Where-Object { $_.NeedAck })
  [void](Add-Label $alertInner $script:AlertTitle $FontTitle $ColChgFg $x $y $W); $y += 30
  if ($script:AlertSub) { [void](Add-Label $alertInner $script:AlertSub $FontSmall $ColMuted $x $y $W); $y += 22 }
  $y += 4
  foreach ($ln in $items) {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point($x, $y); $panel.Size = New-Object System.Drawing.Size($W, 10)
    $panel.BackColor = $(if ($ln.Warn) { $ColBadBg } elseif ($ln.In) { $ColChgBg } else { $ColSurface })
    $panel.BorderStyle = 'FixedSingle'
    $fore = $(if ($ln.Warn) { $ColBadFg } elseif ($ln.In) { $ColChgFg } else { $ColFg })
    $tw = $W - 20; if ($ln.NeedAck -or $ln.Acked) { $tw = $W - 120 }
    $l = Add-Label $panel ([string]$ln.Text) $FontBase $fore 8 7 $tw
    $ph = [Math]::Max(36, $l.PreferredHeight + 14)
    if ($ln.NeedAck) {
      $b = Add-Btn $panel '확인했어요' ($W - 104) ([int](($ph - 30) / 2)) 92 { $r = [int]$this.Tag; Send-Ack $r; foreach ($it in @($script:AlertItems)) { if ($it.Row -eq $r) { $it.NeedAck = $false; $it.Acked = $true } }; Render-Alert }
      $b.Tag = $ln.Row; $b.BackColor = $ColAccent; $b.ForeColor = [System.Drawing.Color]::White; $b.FlatAppearance.BorderColor = $ColAccent; $b.Font = $FontBold
    } elseif ($ln.Acked) { [void](Add-Label $panel '✓ 확인함' $FontSmall $ColOkFg ($W - 80) ([int](($ph - 18) / 2)) 70) }
    $panel.Size = New-Object System.Drawing.Size($W, $ph)
    $alertInner.Controls.Add($panel)
    $y += $ph + 6
  }
  $y += 8
  if ($need.Count) {
    $hint = Add-Label $alertInner ('확인 안 한 변동 ' + $need.Count + '건은 수업 1시간 전과 내일 아침에 다시 알려 드려요.') $FontSmall $ColMuted $x $y $W; $y += $hint.PreferredHeight + 8
    [void](Add-Btn $alertInner '나중에' $x $y 90 { $alert.Hide() })
    [void](Add-Btn $alertInner '자세히 보기' ($x + 96) $y 100 { $alert.Hide(); Show-Popup })
  } else {
    $ok = Add-Btn $alertInner '알겠어요' $x $y 100 { $alert.Hide() }
    $ok.BackColor = $ColAccent; $ok.ForeColor = [System.Drawing.Color]::White; $ok.FlatAppearance.BorderColor = $ColAccent; $ok.Font = $FontBold
    [void](Add-Btn $alertInner '자세히 보기' ($x + 106) $y 100 { $alert.Hide(); Show-Popup })
  }
  $y += 44
  $alertInner.ResumeLayout()
  $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $h = [Math]::Min($y + 40, $wa.Height - 80)
  $alert.Size = New-Object System.Drawing.Size(440, $h)
  $alert.Location = New-Object System.Drawing.Point(($wa.Left + [int](($wa.Width - 440) / 2)), ($wa.Top + [int](($wa.Height - $h) / 2)))
}
function Show-Alert([string]$Title, [string]$Sub, $Items) {
  $list = @($Items | Where-Object { $_ })
  if (-not $list.Count) { return }
  # 이미 떠 있는 창이면 항목을 합침
  if ($alert.Visible) {
    $have = @($script:AlertItems | ForEach-Object { [string]$_.Text })
    foreach ($it in $list) { if ($have -notcontains [string]$it.Text) { $script:AlertItems += $it } }
  } else { $script:AlertItems = $list; $script:AlertTitle = $Title; $script:AlertSub = $Sub }
  Render-Alert
  if (-not $alert.Visible) { $alert.Show() }
  $alert.Activate(); $alert.BringToFront()
  if ([bool]$script:Cfg.Sound) { try { [System.Media.SystemSounds]::Exclamation.Play() } catch { } }
  try { $tray.BalloonTipTitle = $Title; $tray.BalloonTipText = [string]$list[0].Text; $tray.ShowBalloonTip(5000) } catch { }
}

# ---------- 설정 창 ----------
$script:InDialog = $false
$StartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) '내 시간표.lnk'
function Set-Startup([bool]$On) {
  if ($On) {
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($StartupLnk)
    $vbs = Join-Path $PSScriptRoot '내 시간표 실행.vbs'
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $psArgs = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $PSCommandPath + '"'
    if ($Launcher -and (Test-Path $Launcher)) {
      # 내 시간표.exe 로 실행한 경우: exe 를 그대로 등록
      $lnk.TargetPath = $Launcher
      $lnk.Arguments = ''
    } elseif (Test-Path $vbs) {
      # 창이 전혀 뜨지 않는 방식 (VBScript로 숨겨서 실행)
      $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
      $lnk.Arguments = '"' + $vbs + '"'
    } elseif ([Environment]::OSVersion.Version.Build -ge 17763) {
      # 윈도우 10(1809) 이상: 콘솔 없이 실행
      $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\conhost.exe'
      $lnk.Arguments = '--headless "' + $ps + '" ' + $psArgs
    } else {
      $lnk.TargetPath = $ps
      $lnk.Arguments = $psArgs
    }
    $lnk.WorkingDirectory = $(if ($Launcher -and (Test-Path $Launcher)) { Split-Path $Launcher } else { $PSScriptRoot })
    $lnk.WindowStyle = 7
    $lnk.Description = '내 시간표'
    $lnk.Save()
  } elseif (Test-Path $StartupLnk) { Remove-Item $StartupLnk -Force }
}

function New-Lbl($Parent, [string]$Text, [int]$X, [int]$Y) { $l = New-Object System.Windows.Forms.Label; $l.Text = $Text; $l.Location = New-Object System.Drawing.Point($X, $Y); $l.AutoSize = $true; $Parent.Controls.Add($l); return $l }
function New-Box($Parent, [int]$X, [int]$Y, [int]$W, [string]$Val, [bool]$Secret = $false) {
  $t = New-Object System.Windows.Forms.TextBox; $t.Location = New-Object System.Drawing.Point($X, $Y); $t.Width = $W; $t.Text = $Val
  $t.UseSystemPasswordChar = $Secret; $Parent.Controls.Add($t); return $t
}

function Show-Settings {
  $script:InDialog = $true
  try {
    $script:dlg_d = New-Object System.Windows.Forms.Form
    $script:dlg_d.Text = '내 시간표 설정'; $script:dlg_d.Font = $FontBase
    $script:dlg_d.ClientSize = New-Object System.Drawing.Size(460, 500)
    $script:dlg_d.StartPosition = 'CenterScreen'; $script:dlg_d.FormBorderStyle = 'FixedDialog'; $script:dlg_d.MaximizeBox = $false; $script:dlg_d.MinimizeBox = $false; $script:dlg_d.TopMost = $true
    [void](New-Lbl $script:dlg_d '개인 코드 (학교 메일로 받은 8자리)' 16 14)
    $script:dlg_tCode = New-Box $script:dlg_d 16 36 300 $script:Code $true
    $script:dlg_bChk = New-Object System.Windows.Forms.Button; $script:dlg_bChk.Text = '확인'; $script:dlg_bChk.Location = New-Object System.Drawing.Point(324, 34); $script:dlg_bChk.Size = New-Object System.Drawing.Size(120, 28); $script:dlg_d.Controls.Add($script:dlg_bChk)
    $script:dlg_lMsg = New-Lbl $script:dlg_d '' 16 68; $script:dlg_lMsg.ForeColor = $ColMuted; $script:dlg_lMsg.MaximumSize = New-Object System.Drawing.Size(428, 0)
    [void](New-Lbl $script:dlg_d 'PC 앱 데이터 주소 (보통은 이미 들어 있어요)' 16 104)
    $script:dlg_tUrl = New-Box $script:dlg_d 16 126 428 ([string]$script:Cfg.DataUrl)
    [void](New-Lbl $script:dlg_d '주간 시간표 페이지 주소 (학교 계정으로 열려요)' 16 162)
    $script:dlg_tPage = New-Box $script:dlg_d 16 184 428 ([string]$script:Cfg.PageUrl)
    $script:dlg_chk = New-Object System.Windows.Forms.CheckBox; $script:dlg_chk.Text = '윈도우를 켤 때 자동으로 실행'; $script:dlg_chk.Location = New-Object System.Drawing.Point(16, 222); $script:dlg_chk.AutoSize = $true
    $script:dlg_chk.Checked = (Test-Path $StartupLnk); $script:dlg_d.Controls.Add($script:dlg_chk)
    $sep = New-Lbl $script:dlg_d '알림' 16 254; $sep.Font = $FontBold
    $script:dlg_snd = New-Object System.Windows.Forms.CheckBox; $script:dlg_snd.Text = '알림 창이 뜰 때 소리 내기'; $script:dlg_snd.Location = New-Object System.Drawing.Point(16, 278); $script:dlg_snd.AutoSize = $true
    $script:dlg_snd.Checked = [bool]$script:Cfg.Sound; $script:dlg_d.Controls.Add($script:dlg_snd)
    [void](New-Lbl $script:dlg_d '바뀐 수업 시작 전 미리 알림' 16 306)
    $script:dlg_pre = New-Object System.Windows.Forms.ComboBox; $script:dlg_pre.DropDownStyle = 'DropDownList'; $script:dlg_pre.Location = New-Object System.Drawing.Point(230, 302); $script:dlg_pre.Size = New-Object System.Drawing.Size(120, 26)
    [void]$script:dlg_pre.Items.AddRange(@('안 함', '5분 전', '10분 전', '15분 전', '30분 전'))
    $pmNow = 0; try { $pmNow = [int]$script:Cfg.PreMin } catch { }
    $pi = [array]::IndexOf(@(0, 5, 10, 15, 30), $pmNow); if ($pi -lt 0) { $pi = 2 }; $script:dlg_pre.SelectedIndex = $pi
    $script:dlg_d.Controls.Add($script:dlg_pre)
    $script:dlg_eve = New-Object System.Windows.Forms.CheckBox; $script:dlg_eve.Text = '퇴근 전 다음 날 바뀐 수업 요약'; $script:dlg_eve.Location = New-Object System.Drawing.Point(16, 336); $script:dlg_eve.AutoSize = $true
    $script:dlg_eve.Checked = [bool]$script:Cfg.EveOn; $script:dlg_d.Controls.Add($script:dlg_eve)
    $script:dlg_evt = New-Object System.Windows.Forms.ComboBox; $script:dlg_evt.DropDownStyle = 'DropDownList'; $script:dlg_evt.Location = New-Object System.Drawing.Point(230, 332); $script:dlg_evt.Size = New-Object System.Drawing.Size(120, 26)
    [void]$script:dlg_evt.Items.AddRange(@('15:00', '15:30', '16:00', '16:30', '17:00'))
    $script:dlg_evt.SelectedItem = [string]$script:Cfg.EveTime; if ($null -eq $script:dlg_evt.SelectedItem) { $script:dlg_evt.SelectedIndex = 3 }
    $script:dlg_d.Controls.Add($script:dlg_evt)
    $hint2 = New-Lbl $script:dlg_d '새 변동 알림 창과 확인 안 한 변동 재알림(수업 1시간 전·다음 날 아침)은 항상 켜져 있어요.' 16 364; $hint2.ForeColor = $ColMuted; $hint2.MaximumSize = New-Object System.Drawing.Size(428, 0)
    $script:dlg_upd = New-Object System.Windows.Forms.CheckBox; $script:dlg_upd.Text = ('새 버전이 나오면 자동으로 업데이트 (지금 v' + $AppVersion + ')'); $script:dlg_upd.Location = New-Object System.Drawing.Point(16, 396); $script:dlg_upd.AutoSize = $true
    $script:dlg_upd.Checked = [bool]$script:Cfg.AutoUpdate; $script:dlg_d.Controls.Add($script:dlg_upd)
    $hint = New-Lbl $script:dlg_d '개인 코드는 이 PC의 내 Windows 계정으로 암호화해서 저장해요. 다른 분께 알려 주지 마세요.' 16 424; $hint.ForeColor = $ColMuted; $hint.MaximumSize = New-Object System.Drawing.Size(428, 0)
    $script:dlg_lErr = New-Lbl $script:dlg_d '' 16 456; $script:dlg_lErr.ForeColor = $ColBadFg; $script:dlg_lErr.MaximumSize = New-Object System.Drawing.Size(428, 0)
    $ok = New-Object System.Windows.Forms.Button; $ok.Text = '저장'; $ok.Location = New-Object System.Drawing.Point(262, 460); $ok.Size = New-Object System.Drawing.Size(88, 32); $script:dlg_d.Controls.Add($ok)
    $cancel = New-Object System.Windows.Forms.Button; $cancel.Text = '취소'; $cancel.Location = New-Object System.Drawing.Point(356, 460); $cancel.Size = New-Object System.Drawing.Size(88, 32); $cancel.DialogResult = 'Cancel'; $script:dlg_d.Controls.Add($cancel)
    $script:dlg_d.CancelButton = $cancel
    $script:dlg_who = ''

    $script:dlg_bChk.Add_Click({
      $script:dlg_lMsg.ForeColor = $ColMuted; $script:dlg_lMsg.Text = '확인하는 중이에요...'; [System.Windows.Forms.Application]::DoEvents()
      try {
        $r = Invoke-Sheet @{ days = '1' } $script:dlg_tUrl.Text $script:dlg_tCode.Text $script:dlg_tPage.Text
        $script:dlg_who = [string]$r.name
        $script:dlg_lMsg.ForeColor = $ColFg
        $script:dlg_lMsg.Text = [string]$r.school + ' ' + $script:dlg_who + ' 선생님으로 확인됐어요. 저장을 눌러 주세요.'
      } catch { $script:dlg_who = ''; $script:dlg_lMsg.ForeColor = $ColBadFg; $script:dlg_lMsg.Text = '확인하지 못했어요: ' + $_.Exception.Message }
    })
    $ok.Add_Click({
      if (-not $script:dlg_tCode.Text.Trim() -or -not $script:dlg_tUrl.Text.Trim()) { $script:dlg_lErr.Text = '개인 코드와 데이터 주소를 넣어 주세요.'; return }
      $script:dlg_d.DialogResult = 'OK'
    })

    if ($script:dlg_d.ShowDialog() -eq 'OK') {
      $script:Cfg.DataUrl = $script:dlg_tUrl.Text.Trim()
      $script:Code = $script:dlg_tCode.Text.Trim().ToUpper(); $script:Cfg.CodeEnc = Protect-Text $script:Code
      if ($script:dlg_who) { $script:Cfg.Name = $script:dlg_who }
      $script:Cfg.PageUrl = $script:dlg_tPage.Text.Trim()
      $script:Cfg.Sound = [bool]$script:dlg_snd.Checked
      $script:Cfg.PreMin = @(0, 5, 10, 15, 30)[[Math]::Max(0, $script:dlg_pre.SelectedIndex)]
      $script:Cfg.EveOn = [bool]$script:dlg_eve.Checked
      $script:Cfg.EveTime = [string]$script:dlg_evt.SelectedItem
      $script:Cfg.AutoUpdate = [bool]$script:dlg_upd.Checked
      Save-Cfg
      try { Set-Startup $script:dlg_chk.Checked } catch { [void][System.Windows.Forms.MessageBox]::Show('자동 실행을 등록하지 못했어요: ' + $_.Exception.Message, '내 시간표') }
      $script:Sig = $null
      Refresh $false
      Show-Popup
    }
  } finally { $script:InDialog = $false }
}

# ---------- 트레이 ----------
$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = $IconNormal
$tray.Text = '내 시간표'
$tray.Visible = $true
$menu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('열기', $null, { Show-Popup })
[void]$menu.Items.Add('주간 시간표 열기', $null, { Open-Page })
[void]$menu.Items.Add('새로고침', $null, { Refresh $false })
[void]$menu.Items.Add('확인 안 한 변동 보기', $null, { $n = @(Get-ChangeLines | Where-Object { $_.NeedAck }); if ($n.Count) { Show-Alert ('확인 안 한 변동 ' + $n.Count + '건') '[확인했어요]를 눌러 주세요.' $n } else { Show-Balloon '내 시간표' '확인 안 한 변동이 없어요.' } })
[void]$menu.Items.Add('설정', $null, { Show-Settings })
[void]$menu.Items.Add('업데이트 확인', $null, { if (-not (Check-Update $true)) { Show-Balloon '내 시간표' ('지금 v' + $AppVersion + ' · 최신 버전이에요.') } })
[void]$menu.Items.Add('-')
[void]$menu.Items.Add('종료', $null, { $tray.Visible = $false; [System.Windows.Forms.Application]::Exit() })
$tray.ContextMenuStrip = $menu
$tray.Add_MouseClick({
  if ($_.Button -ne 'Left') { return }
  if ($popup.Visible) { $popup.Hide(); return }
  if (((Get-Date) - $script:HiddenAt).TotalMilliseconds -lt 400) { return }   # 방금 아이콘 클릭으로 닫힌 경우
  Show-Popup
})
$tray.Add_BalloonTipClicked({ Show-Popup })

# 수업 시간(평일 07:00~18:30)에는 10분마다, 그 밖에는 1시간마다
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 10 * 60 * 1000
$script:Tick = 0
$timer.Add_Tick({
  $script:Tick++
  $n = Get-Date; $m = $n.Hour * 60 + $n.Minute; $wd = [int]$n.DayOfWeek
  $school = ($wd -ge 1 -and $wd -le 5 -and $m -ge 420 -and $m -le 1110)
  if ($school -or ($script:Tick % 6) -eq 0) { Refresh $true }
  if (-not $alert.Visible -and -not $popup.Visible) { [void](Check-Update) }
})
$timer.Start()

# 1분마다 지금 교시·다음 수업 표시만 다시 계산 (서버에 묻지 않음)
$minute = New-Object System.Windows.Forms.Timer
$minute.Interval = 60 * 1000
$minute.Add_Tick({ Check-Evening; Check-Reminders; Update-Tray; if ($popup.Visible) { Render-Popup } })
$minute.Start()

# 처음 시작
$ctx = New-Object System.Windows.Forms.ApplicationContext
$boot = New-Object System.Windows.Forms.Timer
$boot.Interval = 500
$boot.Add_Tick({
  $boot.Stop()
  if (Test-Path $StartupLnk) { try { Set-Startup $true } catch { } }   # 예전 방식으로 등록된 자동 실행을 창 없는 방식으로 고쳐 둠
  if (-not (Is-Ready)) {
    $tray.BalloonTipTitle = '내 시간표'
    $tray.BalloonTipText = '처음 한 번 설정이 필요해요. 이 알림이나 아이콘을 눌러 주세요.'
    $tray.ShowBalloonTip(8000)
    Show-Settings
  } else {
    $before = [string]$script:Cfg.MornDay
    Refresh $true
    Check-Evening
    if (Check-Update) { return }
  }
})
$boot.Start()
[System.Windows.Forms.Application]::Run($ctx)

$tray.Visible = $false
$tray.Dispose()

} catch {
  [void][System.Windows.Forms.MessageBox]::Show('내 시간표를 실행하지 못했어요.' + "`r`n`r`n" + $_.Exception.Message, '내 시간표', 'OK', 'Error')
} finally {
  try { $mutex.ReleaseMutex() } catch { }
}
