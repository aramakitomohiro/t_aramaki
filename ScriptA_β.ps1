#===========================
#ScriptA_β.ps1
#外接メール送信_メール送信準備
#背景:2026年のOA更改に伴い、外接系でのRPA実行が困難となったことにより作成
#処理内容:
# - ユーザー領域のCSVを読み込み
# - 形式検証＆件数集計
# - 送信内容の確認ダイアログ
# - 問題なければ ProcessingArea へ安全に移送
# ポイント:
# - INIはスクリプトの相対パスで読取
# - CSVは UserArea（絶対パス）から拾う
#起動契機:
# - 外接系共有フォルダのScriptA_β.lnkファイルをユーザーが実行時
# ===========================

param(
  [string]$IniPath = "$PSScriptRoot\mailsettings.ini"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

### A-0: ログ出力用関数（INFO/WARN/ERRORレベルでログを出力）
function Write-Log {
  param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
  $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
  $line = "$ts [$Level] $Message"
  Write-Host $line
  try {
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
  } catch {}
}

### A-1: INIファイルを読み込んでハッシュテーブル化する関数
function Get-Ini {
  param([string]$Path)
  if (-not (Test-Path $Path)) { throw "INIが見つかりません: $Path" }
  $ini = @{}; $sec='General'; $ini[$sec]=@{}
  foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
    $s=$line.Trim(); if (-not $s -or $s -match '^#') { continue }
    if ($s -match '^\[(.+?)\]') { $sec=$matches[1]; if (-not $ini[$sec]){$ini[$sec]=@{}}; continue }
    if ($s -match '^(.*?)\s*=\s*(.*)$') { $ini[$sec][$matches[1].Trim()]=$matches[2].Trim() }
  }
  return $ini
}

### A-2: ヘッダー付きでCSVを読み込む関数（カラム名はINIから取得）
function Read-Csv-WithHeader {
  param([string]$FilePath,[hashtable]$Ini)
  $c=$Ini['Columns']
  $headers=@($c.Col1,$c.Col2,$c.Col3,$c.Col4)
  Import-Csv -LiteralPath $FilePath -Encoding UTF8 -Header $headers
}

### A-3: 初期化（パス・ログ）
### INIファイルから各種パスを取得し、ログ出力先を準備
$ini = Get-Ini -Path $IniPath
$paths = $ini['Paths']
$userDir = $paths['UserArea']
$procDir = $paths['ProcessingArea']
$logDir  = $paths['LogDir']
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$script:LogFile = Join-Path $logDir ("A_" + (Get-Date -Format 'yyyy_MM_dd') + ".log")

# 多重起動チェック用のロックファイル存在確認
$lockFile = Join-Path $logDir "処理開始.txt"
if (Test-Path $lockFile) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("メール送信スクリプトが起動しています。", "警告", "OK", "Warning")
    Write-Log "メール送信スクリプトが起動しています。処理中止" 'WARN'
    exit 1
}
# 古いロックファイルが無いため作成します
Set-Content -Path $lockFile -Value "処理中" -Encoding UTF8
Write-Log "Start ScriptA. UserArea=$userDir, ProcessingArea=$procDir"

### A-4: ユーザー領域のCSV列挙
### ユーザー領域(UserArea)からCSVファイルを列挙
$csvFiles = Get-ChildItem -LiteralPath $userDir -Filter '*.csv' -File -ErrorAction SilentlyContinue | Sort-Object Name
if (-not $csvFiles) { Write-Log "CSVなし。処理終了"; exit 0 }

### A-5: 形式検証＆件数集計（Toが空／送信済の検出）
### 各CSVの行ごとに「宛先(To)が空」「未送信(Col1)」をチェックし、警告・集計
$cols=$ini['Columns']; $toCol=$cols.Col2; $sentCol=$cols.Col1
$total=0; $ready=0; $warns=@()
foreach($f in $csvFiles){
  $rows = Read-Csv-WithHeader -FilePath $f.FullName -Ini $ini
  $total += $rows.Count
  $i=0
  foreach($r in $rows){ $i++
    if (-not $r.$toCol){ $warns += "$($f.Name) ${i}行目: 宛先無し" }
    if (-not $r.$sentCol){ $ready++ }
  }
}

### A-6: 送信前の確認ポップアップ（誤送信防止）
### 送信前に確認ダイアログを表示し、ユーザーに最終確認（警告があれば抜粋表示）
$needConfirm = ($ini['General']['Confirm'] -eq 'true')
if ($needConfirm) {
  Add-Type -AssemblyName System.Windows.Forms
  $summary = "対象ファイル: $($csvFiles.Count) 件`r`n総行数: $total`r`n未送信行(送信候補): $ready`r`n警告: $($warns.Count) 件"
  if ($warns.Count -gt 0){ $summary += "`r`n----警告抜粋----`r`n" + ($warns | Select-Object -First 5 -Join "`r`n") }
  $res = [System.Windows.Forms.MessageBox]::Show($summary, '送信準備 確認', 'OKCancel', 'Warning')
  if ($res -ne 'OK'){ Write-Log "ユーザー取消"; exit 1 }
}

### A-7: ProcessingAreaへ安全に移送（名前衝突を避ける）
### 各CSVファイルをProcessingAreaへタイムスタンプ付きで移動（重複防止）
foreach($f in $csvFiles){
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $dest  = Join-Path $procDir ($f.BaseName + "_" + $stamp + $f.Extension)
  Write-Log "Move: $($f.FullName) -> $dest"
  Move-Item -LiteralPath $f.FullName -Destination $dest -Force
}
Write-Log "移送完了。スクリプトB（JP1）が拾います"