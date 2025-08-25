# PowerShellスクリプト動作解説・設計思想・注意点

## 1. システム全体概要

### 1.1 システム構成図
```
[ユーザー] 
    ↓ CSVファイル配置
[UserArea]
    ↓ ScriptA実行（手動）
[検証・確認ダイアログ]
    ↓ 承認後
[ProcessingArea] 
    ↓ ScriptB実行（JP1自動）
[メール送信] → [Exchange Server] → [m-FILTER] → [外部]
    ↓ 完了後
[UserArea（結果返却）] & [Archive（保管）]
```

### 1.2 設計思想

#### **安全性優先の設計**
- **段階的承認**: 人間による確認→自動実行の2段階
- **誤送信防止**: 確認ダイアログ、From固定化
- **監査証跡**: 詳細ログ、アーカイブ保管

#### **運用性重視の設計**
- **設定外部化**: INIファイルによる柔軟な設定変更
- **明確な責任分離**: 準備（手動）と実行（自動）の分離
- **エラーレベル管理**: 明確な終了コードによる状態管理

#### **保守性を考慮した設計**
- **ログ中心**: すべての処理をログで追跡可能
- **ファイル管理**: タイムスタンプによる重複回避
- **段階的処理**: 各ステップが独立して動作

## 2. ScriptA_β.ps1 詳細解説

### 2.1 処理フロー
```
起動
 ↓
[A-0] ログ機能初期化
 ↓  
[A-1] INI設定読み込み
 ↓
[A-2] CSV読み込み関数準備
 ↓
[A-3] 初期化（パス取得、ログファイル作成、多重起動チェック）
 ↓
[A-4] UserArea内のCSVファイル列挙
 ↓
[A-5] 各CSVの形式検証・件数集計
 ↓
[A-6] 送信前確認ダイアログ（任意）
 ↓
[A-7] ProcessingAreaへ安全移送
 ↓
終了
```

### 2.2 重要な関数の動作

#### Write-Log関数
```powershell
function Write-Log {
  param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
  $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
  $line = "$ts [$Level] $Message"
  Write-Host $line  # コンソール出力
  try {
    if ($script:LogFile) { 
      Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 
    }
  } catch {}
}
```

**特徴**:
- **ミリ秒精度のタイムスタンプ**: 処理順序の正確な把握
- **レベル分け**: INFO（通常）、WARN（警告）、ERROR（エラー）
- **二重出力**: コンソール表示とファイル保存
- **エラー無視**: ログ出力自体のエラーは処理を止めない

#### Get-Ini関数
```powershell
function Get-Ini {
  param([string]$Path)
  if (-not (Test-Path $Path)) { throw "INIが見つかりません: $Path" }
  $ini = @{}; $sec='General'; $ini[$sec]=@{}
  foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
    $s=$line.Trim(); if (-not $s -or $s -match '^#') { continue }  # 空行・コメント除外
    if ($s -match '^\[(.+?)\]') { 
      $sec=$matches[1]; if (-not $ini[$sec]){$ini[$sec]=@{}}; continue 
    }
    if ($s -match '^(.*?)\s*=\s*(.*)$') { 
      $ini[$sec][$matches[1].Trim()]=$matches[2].Trim() 
    }
  }
  return $ini
}
```

**特徴**:
- **セクション対応**: [セクション名]形式をサポート
- **コメント対応**: #で始まる行を無視
- **空行処理**: 空行を適切にスキップ
- **ハッシュテーブル化**: 効率的なアクセスのためのデータ構造変換

### 2.3 多重起動制御の仕組み

#### ロックファイル管理
```powershell
# 起動時：既存チェック
$lockFile = Join-Path $logDir "処理開始.txt"
if (Test-Path $lockFile) {
    # GUIでユーザーに通知
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "メール送信スクリプトが起動しています。", 
        "警告", "OK", "Warning"
    )
    Write-Log "メール送信スクリプトが起動しています。処理中止" 'WARN'
    exit 1
}

# ロックファイル作成
Set-Content -Path $lockFile -Value "処理中" -Encoding UTF8
```

**重要ポイント**:
- **GUI警告**: コンソールを見ないユーザーにも確実に通知
- **即座終了**: 多重起動を検出したら処理を継続しない
- **ログ記録**: 多重起動の試行も監査ログに記録

### 2.4 CSV検証ロジック
```powershell
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
```

**検証内容**:
- **宛先チェック**: メールアドレス列の空值確認
- **送信状態確認**: 未送信行のカウント
- **警告収集**: 問題のある行の詳細記録
- **統計情報**: 総行数、送信候補数の集計

### 2.5 確認ダイアログの実装
```powershell
$needConfirm = ($ini['General']['Confirm'] -eq 'true')
if ($needConfirm) {
  Add-Type -AssemblyName System.Windows.Forms
  $summary = "対象ファイル: $($csvFiles.Count) 件`r`n総行数: $total`r`n未送信行(送信候補): $ready`r`n警告: $($warns.Count) 件"
  if ($warns.Count -gt 0){ 
    $summary += "`r`n----警告抜粋----`r`n" + ($warns | Select-Object -First 5 -Join "`r`n") 
  }
  $res = [System.Windows.Forms.MessageBox]::Show($summary, '送信準備 確認', 'OKCancel', 'Warning')
  if ($res -ne 'OK'){ Write-Log "ユーザー取消"; exit 1 }
}
```

**特徴**:
- **設定制御**: INIファイルで確認の有無を制御
- **詳細表示**: ファイル数、行数、警告の要約表示
- **警告抜粋**: 問題がある場合は最初の5件を表示
- **キャンセル対応**: ユーザーがNOを選択した場合の処理中止

## 3. ScriptB_β.ps1 詳細解説

### 3.1 処理フロー
```
起動（JP1から5分間隔）
 ↓
[B-0〜B-2] 基本機能初期化
 ↓
[B-6] INI読み込み・ログ初期化・ロックファイル確認
 ↓
[B-7] ProcessingArea内のCSVファイル検索
 ↓
各ファイルについて：
  [B-8] テンプレート選択（ファイル名キーワード照合）
  [B-9] CSVデータ読み込み・検証
  [B-10] 行ごとメール送信・送信日書き戻し
  [B-11] 結果ファイル返却・アーカイブ退避
 ↓
終了（0=成功, 1=処理なし, 2=一部失敗, 3=致命的エラー）
```

### 3.2 テンプレート選択の仕組み

#### キーワードマッチング
```powershell
# INI設定例
[KOZA_KAISETSU]
CsvKeyword=口座開設_メール送信時に使用

# マッチング処理
$section=$null
foreach($sec in $ini.Keys){
  if($sec -in 'General','SMTP','Columns','Paths'){ continue }
  if($file.Name -like "*$($ini[$sec]['CsvKeyword'])*"){ 
    $section=$sec; break 
  }
}
```

**特徴**:
- **部分マッチ**: ファイル名にキーワードが含まれていればマッチ
- **優先順位**: INIファイルの記述順でマッチング
- **スキップ処理**: マッチするテンプレートがない場合はファイルをスキップ

#### メールテンプレート合成
```powershell
function Compose-Mail {
  param([hashtable]$Ini,[string]$Section,[pscustomobject]$Row)
  $sec=$Ini[$Section]
  $subject = if($sec.Subject){ $sec.Subject } else { [string]$Row.($Ini['Columns'].Col3) }
  $body    = if($sec.Body)   { $sec.Body }    else { [string]$Row.($Ini['Columns'].Col4) }
  $body=$body -replace '@CRLF', "`r`n"
  return @{ Subject=$subject; Body=$body }
}
```

**優先順位**:
1. **INI設定値**: テンプレートセクションの件名・本文
2. **CSV個別値**: 各行のSubject1・Body1列
3. **改行変換**: @CRLFを実際の改行コードに変換

### 3.3 メール送信処理の詳細

#### SMTP送信関数
```powershell
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
  try{ $cli.Send($msg); return $true }
  catch{ Write-Log "送信失敗: $($_.Exception.Message)" 'WARN'; return $false }
}
```

**セキュリティ対策**:
- **From固定**: 送信元偽装の防止
- **複数宛先対応**: セミコロン区切りでの複数宛先
- **SSL対応**: 暗号化通信のサポート
- **認証対応**: SMTP認証の設定可能

### 3.4 送信状態管理

#### 送信日の書き戻し
```powershell
for($i=0; $i -lt $rows.Count; $i++){
  $r=$rows[$i]
  if($r.$sentCol){ continue }  # 既に送信済みの行はスキップ

  # メール送信処理
  $success = Send-MailSmtp -Smtp $smtp -To $to -Subject $mail.Subject -Body $mail.Body -Cc $general['Cc'] -Bcc $general['Bcc']
  
  if($success){
    $rows[$i].$sentCol = (Get-Date).ToString('yyyy/MM/dd')  # 送信日記録
    $changed=$true; $okCount++
  } else {
    $ngCount++; $anyFailure=$true
  }
}
```

**重要ポイント**:
- **冪等性**: 送信済みの行は再送信しない
- **日付形式**: yyyy/MM/dd形式での送信日記録
- **状態管理**: 成功・失敗数のカウント
- **部分成功**: 一部成功した場合も結果を保存

### 3.5 ファイル管理とアーカイブ

#### 結果ファイルの返却
```powershell
# 送信結果をCSVに保存
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

# アーカイブ退避
$destArc = Join-Path $archiveDir ($file.BaseName + "_" + $stamp + $file.Extension)
Move-Item -LiteralPath $file.FullName -Destination $destArc -Force
```

**ファイル操作の特徴**:
- **原子性**: 一時ファイル経由での安全な更新
- **重複回避**: タイムスタンプによるファイル名の一意性確保
- **二重保管**: ユーザー領域への返却とアーカイブの両方
- **トレーサビリティ**: 処理日時がファイル名から特定可能

## 4. mailsettings.ini 設定詳細

### 4.1 セクション構成

#### [General] - 一般設定
```ini
[General]
Bcc=gpa@kain.co.jp          # 全メールに追加されるBcc
CsvEncoding=UTF8            # CSV文字エンコーディング
```

#### [Paths] - パス設定
```ini
[Paths]
UserArea=\\fileshare\mail\UserArea              # ユーザー操作領域
ProcessingArea=\\fileshare\mail\ProcessingArea  # 処理作業領域  
LogDir=\\fileshare\mail\Logs                    # ログ保存先
ArchiveDir=\\fileshare\mail\Archive             # アーカイブ保存先
```

#### [SMTP] - メールサーバー設定
```ini
[SMTP]
Server=localhost    # Exchange Serverのホスト名
Port=25            # SMTPポート番号
From=k-app@kain.co.jp  # 送信元アドレス（固定）
```

#### [Columns] - CSV列マッピング
```ini
[Columns]
Col1=MailSentDate  # 送信日列（書き戻し対象）
Col2=MailAddress   # 宛先メールアドレス列
Col3=Subject1      # 件名列（テンプレート未定義時）
Col4=Body1         # 本文列（テンプレート未定義時）
```

### 4.2 テンプレートセクション
```ini
[KOZA_KAISETSU]
CsvKeyword=口座開設_メール送信時に使用
Subject=【口座開設】お手続きの結果について
Body=いつもご利用ありがとうございます@CRLF@CRLFお手続きが完了いたしました@CRLF本メールは自動送信です
```

**設定のポイント**:
- **キーワード**: ファイル名にこの文字列が含まれる場合に適用
- **@CRLF**: 改行コードのプレースホルダー（送信時に\r\nに変換）
- **固定テンプレート**: 業務種別ごとの標準的なメール内容

## 5. 運用上の重要な注意点

### 5.1 セキュリティ関連
- **From固定化**: 送信元偽装防止のため、Fromアドレスは変更不可
- **Bcc強制追加**: 監査目的でBccが自動追加される
- **パスワード管理**: SMTP認証のパスワードはINIファイルに平文保存（要改善）

### 5.2 運用関連
- **JP1との連携**: ScriptBはJP1から5分間隔で起動される想定
- **手動承認必須**: ScriptAでの人間による確認が必須プロセス
- **ログ監視**: 処理結果は終了コードとログで確認

### 5.3 障害対応
- **多重起動**: ロックファイルで制御されているが、異常終了時は手動削除が必要
- **部分失敗**: 一部メール送信失敗時も処理は継続される
- **ネットワーク障害**: SMTP接続失敗時はログに記録されるが、リトライ機能なし

### 5.4 データ整合性
- **冪等性**: 同じファイルを複数回処理しても重複送信されない
- **アーカイブ**: すべての処理済みファイルは日時付きでアーカイブ保存
- **監査証跡**: ログとアーカイブで完全な処理履歴を保持