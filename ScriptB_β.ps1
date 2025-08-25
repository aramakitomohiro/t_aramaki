#===========================
#ScriptB_β.ps1
#外接メール送信_メール送信実行
#背景:2026年のOA更改に伴い、外接系でのRPA実行が困難となったことにより作成
#処理内容:
# - ProcessingArea のCSVを検出
# - テンプレ選択（CsvKeyword）
# - 1行ずつ:未送信だけ送信（From固定、Bcc固定）→送信日(yyyy/MM/dd)を書戻し
# - 完了後:結果CSVを UserArea へ返却、元をArchiveへ
#起動契機:
# - JP1から5分間隔で起動し、処理対象のCSVファイルがカレントディレクトリにあれば処理開始
#処理結果の判定方法:
# - 0=成功  1=処理なし  2=一部失敗  3=致命的エラー
#===========================

param(
  [string]$IniPath = "$PSScriptRoot\mailsettings.ini"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

### B-0: ログ出力用関数（INFO/WARN/ERRORレベルでログを出力）
function Write-Log {
  param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
  $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
  $line = "$ts [$Level] $Message"
  Write-Host $line
  try { if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } } catch {}
}

### B-1: INIファイルを読み込んでハッシュテーブル化する関数
function Get-Ini {
  param([string]$Path)
  if (-not (Test-Path $Path)) { throw "INIが見つかりません: $Path" }
  $ini=@{}; $sec='General'; $ini[$sec]=@{}
  foreach($line in Get-Content -LiteralPath $Path -Encoding UTF8){
    $s=$line.Trim(); if(-not $s -or $s -match '^[#]'){continue}
    if($s -match '^\[(.+?)\]'){ $sec=$matches[1]; if(-not $ini[$sec]){$ini[$sec]=@{}}; continue }
    if($s -match '^(.*?)\s*=\s*(.*)$'){ $ini[$sec][$matches[1].Trim()]=$matches[2].Trim() }
  }
  return $ini
}

### B-2: ヘッダー付きでCSVを読み込む関数（カラム名はINIから取得）
function Read-Csv-WithHeader {
  param([string]$FilePath,[hashtable]$Ini)
  $c=$Ini['Columns']
  $headers=@($c.Col1,$c.Col2,$c.Col3,$c.Col4)
  Import-Csv -LiteralPath $FilePath -Encoding UTF8 -Header $headers
}

### B-3: CSVの各行について「宛先(To)が空」などの検証を行う関数
function Validate-Csv {
  param([object[]]$Rows,[hashtable]$Ini,[string]$FileName)
  $toCol=$Ini['Columns'].Col2
  $err=0; $i=0
  foreach($r in $Rows){ $i++
    if(-not $r.$toCol){ Write-Log "[$FileName] $i 行目 宛先空" 'WARN'; $err++ }
  }
  return ($err -eq 0)
}

### B-4: メールテンプレートを合成（INI優先、なければCSVのSubject1/Body1）
function Compose-Mail {
  param([hashtable]$Ini,[string]$Section,[pscustomobject]$Row)
  $sec=$Ini[$Section]
  $subject = if($sec.Subject){ $sec.Subject } else { [string]$Row.($Ini['Columns'].Col3) }
  $body    = if($sec.Body)   { $sec.Body }    else { [string]$Row.($Ini['Columns'].Col4) }
  $body=$body -replace '@CRLF', "`r`n"
  return @{ Subject=$subject; Body=$body }
}

### B-5: SMTPでメール送信（From/Bccは固定値、認証やSSLもINIで制御）
function Send-MailSmtp {
  param([hashtable]$Smtp,[string]$To,[string]$Subject,[string]$Body,[string]$Cc,[string]$Bcc)
  $msg = New-Object System.Net.Mail.MailMessage
  $msg.From = $Smtp.From                       # ←固定（偽装を防ぐ）
  $To.Split(';')  | ?{$_} | % { $msg.To.Add($_) }
  if($Cc)  { $Cc.Split(';')  | ?{$_} | % { $msg.CC.Add($_) } }
  if($Bcc) { $Bcc.Split(';') | ?{$_} | % { $msg.Bcc.Add($_) } }
  $msg.Subject=$Subject; $msg.Body=$Body

  $cli = New-Object System.Net.Mail.SmtpClient($Smtp.Server, [int]$Smtp.Port)
  $cli.EnableSsl = [bool]::Parse(($Smtp.EnableSsl ?? 'false'))
  if(($Smtp.Auth ?? 'false') -eq 'true'){
    $cli.UseDefaultCredentials=$false
    $cli.Credentials=New-Object System.Net.NetworkCredential($Smtp.User,$Smtp.Password)
  }
  try{ $cli.Send($msg); return $true }catch{ Write-Log "送信失敗: $($_.Exception.Message)" 'WARN'; return $false }
}

### B-6: 初期化（INIファイル読み込み、ログ設定）
### INIファイルから各種パスを取得し、ログ出力先を準備
$ini = Get-Ini -Path $IniPath
$paths = $ini['Paths']; $procDir=$paths['ProcessingArea']; $userDir=$paths['UserArea']
$logDir=$paths['LogDir']; if(-not (Test-Path $logDir)){ New-Item -ItemType Directory -Path $logDir | Out-Null }
$script:LogFile = Join-Path $logDir ("B_" + (Get-Date -Format 'yyyy_MM_dd') + ".log")
Write-Log "Start ScriptB. ProcessingArea=$procDir"

# 処理開始.txtの存在確認
$lockFile = Join-Path $logDir "処理開始.txt"
if (-not (Test-Path $lockFile)) {
    Write-Log "「処理開始ファイル」が見つかりません。処理を中止します。" 'WARN'
    exit 1
}

### B-7: ProcessingAreaからCSVファイルを列挙。なければ即終了
try {
  $files = Get-ChildItem -LiteralPath $procDir -Filter '*.csv' -File -ErrorAction SilentlyContinue | Sort-Object Name
  if(-not $files){ Write-Log "処理対象なし"; exit 1 }

  $smtp=$ini['SMTP']; $general=$ini['General']
  $cols=$ini['Columns']; $toCol=$cols.Col2; $sentCol=$cols.Col1
  $anyFailure = $false

  foreach($file in $files){
    Write-Log "処理開始: $($file.Name)"

  ### B-8: ファイル名にCsvKeywordが含まれるテンプレートセクションを選択
    $section=$null
    foreach($sec in $ini.Keys){
      if($sec -in 'General','SMTP','Columns','Paths'){ continue }
      if($file.Name -like "*$($ini[$sec]['CsvKeyword'])*"){ $section=$sec; break }
    }
    if(-not $section){ Write-Log "テンプレ未定義のためスキップ: $($file.Name)" 'WARN'; $anyFailure=$true; continue }

  ### B-9: CSVを読み込み、宛先等の検証を実施
    $rows = Read-Csv-WithHeader -FilePath $file.FullName -Ini $ini
    if(-not (Validate-Csv -Rows $rows -Ini $ini -FileName $file.Name)){ $anyFailure=$true; continue }

  ### B-10: 各行ごとに未送信行のみメール送信。成功時は送信日を書き戻し
    $changed=$false; $okCount=0; $ngCount=0
    for($i=0; $i -lt $rows.Count; $i++){
      $r=$rows[$i]
      if($r.$sentCol){ continue }                         # 既に送信済み

      $mail = Compose-Mail -Ini $ini -Section $section -Row $r
      $to = [string]$r.$toCol
      $success = Send-MailSmtp -Smtp $smtp -To $to -Subject $mail.Subject -Body $mail.Body -Cc $general['Cc'] -Bcc $general['Bcc']
      if($success){
        $rows[$i].$sentCol = (Get-Date).ToString('yyyy/MM/dd')  # yyyy/MM/ddで書戻し
        $changed=$true; $okCount++
      } else {
        $ngCount++; $anyFailure=$true
      }
    }
    Write-Log "送信結果: OK=$okCount, NG=$ngCount"


  ### B-11: 送信結果をCSVに保存し、ユーザー領域へ返却。元ファイルはアーカイブへ退避
    if($changed){
      $tmp = "$($file.FullName).tmp"
      $rows | Export-Csv -LiteralPath $tmp -NoTypeInformation -Encoding UTF8
      Move-Item -LiteralPath $tmp -Destination $file.FullName -Force
    }

    # 返却ファイル名に日時を付与
    $stamp=(Get-Date -Format 'yyyyMMdd_HHmmss')
    $returnName = ($file.BaseName + "_result_" + $stamp + $file.Extension)
    $destUser = Join-Path $userDir $returnName
    Copy-Item -LiteralPath $file.FullName -Destination $destUser -Force
    Write-Log "結果返却: $destUser"

    # アーカイブ退避
    $archiveDir = $ini['Paths']['ArchiveDir']
    if(-not (Test-Path $archiveDir)){ New-Item -ItemType Directory -Path $archiveDir | Out-Null }
    $destArc = Join-Path $archiveDir ($file.BaseName + "_" + $stamp + $file.Extension)
    Move-Item -LiteralPath $file.FullName -Destination $destArc -Force
    Write-Log "アーカイブ: $destArc"
  }

  if($anyFailure){ Write-Log "一部失敗あり" 'WARN'; exit 2 } else { Write-Log "正常終了"; exit 0 }
}
catch {
  Write-Log "致命的エラー: $($_.Exception.Message)" 'ERROR'
  exit 3
}
finally {
    # ロックファイルの削除
    if (Test-Path $lockFile) {
        Remove-Item -Path $lockFile -Force
        Write-Log "ロックファイル削除完了"
    }
}