# PowerShellスクリプト詳細コードレビュー

## 1. 全体的な品質・保守性の評価

### 良い点
- **明確な責任分離**: ScriptA（準備）とScriptB（実行）で役割が明確に分かれている
- **詳細なログ出力**: 処理の各段階でINFO/WARN/ERRORレベルでログを記録
- **設定の外部化**: INIファイルによる設定の外部化で運用時の柔軟性を確保
- **エラーハンドリング**: Set-StrictModeとErrorActionPreference='Stop'による厳格なエラー処理

### 改善が必要な点

#### 1.1 コード重複
**問題**: Get-Ini、Write-Log、Read-Csv-WithHeader関数が両スクリプトで重複
```powershell
# 現状：両ファイルで同じ関数を定義
function Get-Ini { ... }  # ScriptA & ScriptB
function Write-Log { ... }  # ScriptA & ScriptB
```

**推奨改善策**:
```powershell
# 共通モジュール化: MailCommon.psm1
function Get-Ini { ... }
function Write-Log { ... }
function Read-Csv-WithHeader { ... }
Export-ModuleMember -Function Get-Ini, Write-Log, Read-Csv-WithHeader

# 各スクリプトでImport
Import-Module "$PSScriptRoot\MailCommon.psm1"
```

#### 1.2 変数名の一貫性
**問題**: 変数名の命名規則が一貫していない
```powershell
$csvFiles   # キャメルケース
$anyFailure # キャメルケース  
$i=0        # 単文字（分かりにくい）
$s=$line.Trim()  # 単文字（分かりにくい）
```

**推奨改善策**:
```powershell
$csvFiles
$hasAnyFailure
$rowIndex = 0
$trimmedLine = $line.Trim()
```

## 2. セキュリティ・誤送信防止の評価

### 良い点
- **From固定化**: 送信元メールアドレスの固定により偽装防止
- **確認ダイアログ**: 送信前の最終確認（INI設定で制御可能）
- **段階的処理**: ScriptAで検証→ScriptBで送信の2段階処理

### セキュリティ上の課題

#### 2.1 パスワードの平文保存
**問題**: SMTP認証のパスワードがINIファイルに平文で保存される
```ini
[SMTP]
User=smtp_user
Password=plain_password  # 危険：平文保存
```

**推奨改善策**:
```powershell
# 暗号化保存・復号化機能
function Set-EncryptedPassword {
    param([string]$PlainPassword)
    $PlainPassword | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
}

function Get-DecryptedPassword {
    param([string]$EncryptedPassword)
    $EncryptedPassword | ConvertTo-SecureString | [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($_))
}
```

#### 2.2 メールアドレス形式の検証不足
**問題**: メールアドレスの形式検証が不十分
```powershell
# 現状：空チェックのみ
if (-not $r.$toCol){ $warns += "$($f.Name) ${i}行目: 宛先無し" }
```

**推奨改善策**:
```powershell
function Test-EmailAddress {
    param([string]$Email)
    try {
        $null = [System.Net.Mail.MailAddress]$Email
        return $true
    } catch {
        return $false
    }
}

# 使用例
if (-not $r.$toCol) { 
    $warns += "$($f.Name) ${rowIndex}行目: 宛先無し" 
} elseif (-not (Test-EmailAddress -Email $r.$toCol)) {
    $warns += "$($f.Name) ${rowIndex}行目: 不正なメールアドレス形式"
}
```

## 3. エラー検知・ハンドリングの評価

### 良い点
- **例外処理**: try-catch-finallyによる適切なエラーハンドリング
- **詳細なログ**: エラー発生時の詳細なログ出力
- **終了コード**: 処理結果に応じた適切な終了コード（0=成功、1=処理なし、2=一部失敗、3=致命的エラー）

### 改善が必要な点

#### 3.1 ネットワークエラーの細かな分類不足
**問題**: SMTP送信失敗の原因分析が不十分
```powershell
# 現状：すべてのエラーを同じように扱う
try{ $cli.Send($msg); return $true }
catch{ Write-Log "送信失敗: $($_.Exception.Message)" 'WARN'; return $false }
```

**推奨改善策**:
```powershell
function Send-MailSmtp {
    param([hashtable]$Smtp,[string]$To,[string]$Subject,[string]$Body,[string]$Cc,[string]$Bcc)
    
    try {
        # メール送信処理
        $cli.Send($msg)
        Write-Log "送信成功: $To" 'INFO'
        return $true
    }
    catch [System.Net.Mail.SmtpFailedRecipientsException] {
        Write-Log "受信者エラー: $To - $($_.Exception.Message)" 'ERROR'
        return $false
    }
    catch [System.Net.Mail.SmtpException] {
        Write-Log "SMTPサーバーエラー: $($_.Exception.Message)" 'ERROR'
        return $false
    }
    catch [System.Net.NetworkInformation.NetworkInformationException] {
        Write-Log "ネットワークエラー: $($_.Exception.Message)" 'ERROR'
        return $false
    }
    catch {
        Write-Log "送信失敗（未知のエラー）: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}
```

#### 3.2 CSVファイル破損時の対処不足
**問題**: CSVファイルが破損している場合の処理が不十分
```powershell
# 現状：Import-Csvが失敗した場合の処理なし
$rows = Read-Csv-WithHeader -FilePath $f.FullName -Ini $ini
```

**推奨改善策**:
```powershell
function Read-Csv-WithHeader {
    param([string]$FilePath,[hashtable]$Ini)
    
    try {
        $c = $Ini['Columns']
        $headers = @($c.Col1, $c.Col2, $c.Col3, $c.Col4)
        
        # ファイルサイズチェック
        $fileInfo = Get-Item -LiteralPath $FilePath
        if ($fileInfo.Length -eq 0) {
            throw "CSVファイルが空です: $FilePath"
        }
        
        # BOM付きUTF-8対応
        $csvContent = Import-Csv -LiteralPath $FilePath -Encoding UTF8 -Header $headers -ErrorAction Stop
        
        # 最低限の列数チェック
        if ($csvContent -and $csvContent[0].PSObject.Properties.Count -lt 4) {
            throw "CSVの列数が不足しています（期待値：4列）: $FilePath"
        }
        
        return $csvContent
    }
    catch {
        Write-Log "CSVファイル読み込みエラー: $FilePath - $($_.Exception.Message)" 'ERROR'
        throw
    }
}
```

## 4. 多重起動制御の評価

### 現在の実装
```powershell
# ScriptA: ロックファイル作成
$lockFile = Join-Path $logDir "処理開始.txt"
if (Test-Path $lockFile) {
    # 警告表示して終了
    exit 1
}
Set-Content -Path $lockFile -Value "処理中" -Encoding UTF8

# ScriptB: ロックファイル確認
if (-not (Test-Path $lockFile)) {
    Write-Log "「処理開始ファイル」が見つかりません。処理を中止します。" 'WARN'
    exit 1
}

# ScriptB終了時: ロックファイル削除
finally {
    if (Test-Path $lockFile) {
        Remove-Item -Path $lockFile -Force
    }
}
```

### 改善点

#### 4.1 プロセス死活監視の不足
**問題**: ScriptAが異常終了した場合、ロックファイルが残り続ける

**推奨改善策**:
```powershell
function Set-ProcessLock {
    param([string]$LockFile)
    
    $lockInfo = @{
        ProcessId = $PID
        ProcessName = $MyInvocation.MyCommand.Name
        StartTime = Get-Date
        MachineName = $env:COMPUTERNAME
    } | ConvertTo-Json
    
    Set-Content -Path $LockFile -Value $lockInfo -Encoding UTF8
}

function Test-ProcessLock {
    param([string]$LockFile)
    
    if (-not (Test-Path $LockFile)) { return $false }
    
    try {
        $lockInfo = Get-Content -LiteralPath $LockFile | ConvertFrom-Json
        $process = Get-Process -Id $lockInfo.ProcessId -ErrorAction SilentlyContinue
        
        if ($process -and $process.ProcessName -eq $lockInfo.ProcessName) {
            return $true  # プロセス実行中
        } else {
            # プロセスが存在しない場合はロックファイル削除
            Remove-Item -LiteralPath $LockFile -Force
            return $false
        }
    } catch {
        # ロックファイル破損時は削除
        Remove-Item -LiteralPath $LockFile -Force
        return $false
    }
}
```

#### 4.2 ロックファイル名の改善
**問題**: 「処理開始.txt」という名前が分かりにくい

**推奨改善策**:
```powershell
$lockFile = Join-Path $logDir "MailScript.lock"
# または
$lockFile = Join-Path $logDir "EmailProcessing_$env:COMPUTERNAME.lock"
```

## 5. 設定の柔軟性評価

### 良い点
- **外部設定ファイル**: INIファイルによる設定の外部化
- **テンプレート機能**: ファイル名キーワードによるテンプレート選択
- **パス設定**: 各種ディレクトリパスの設定可能

### 改善が必要な点

#### 5.1 INI設定の検証不足
**問題**: INI設定値の妥当性検証が不十分

**推奨改善策**:
```powershell
function Test-IniConfiguration {
    param([hashtable]$Ini)
    
    $errors = @()
    
    # 必須セクションの存在確認
    $requiredSections = @('General', 'Paths', 'SMTP', 'Columns')
    foreach ($section in $requiredSections) {
        if (-not $Ini.ContainsKey($section)) {
            $errors += "必須セクションが存在しません: [$section]"
        }
    }
    
    # パスの存在確認（作成可能性も含む）
    if ($Ini['Paths']) {
        foreach ($pathKey in @('UserArea', 'ProcessingArea', 'LogDir', 'ArchiveDir')) {
            $path = $Ini['Paths'][$pathKey]
            if ($path) {
                $parentPath = Split-Path -Path $path -Parent
                if (-not (Test-Path $parentPath)) {
                    $errors += "パスの親ディレクトリが存在しません: $pathKey = $path"
                }
            }
        }
    }
    
    # SMTP設定の検証
    if ($Ini['SMTP']) {
        if (-not $Ini['SMTP']['Server']) {
            $errors += "SMTPサーバーが設定されていません"
        }
        if (-not $Ini['SMTP']['Port'] -or -not ($Ini['SMTP']['Port'] -match '^\d+$')) {
            $errors += "SMTPポートが正しく設定されていません"
        }
    }
    
    if ($errors.Count -gt 0) {
        throw "設定エラー:`n" + ($errors -join "`n")
    }
    
    return $true
}
```

#### 5.2 動的設定の不足
**問題**: 運用中の設定変更に対する対応が不十分

**推奨改善策**:
```powershell
function Watch-ConfigurationChanges {
    param([string]$IniPath, [scriptblock]$OnChange)
    
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = Split-Path -Path $IniPath -Parent
    $watcher.Filter = Split-Path -Path $IniPath -Leaf
    $watcher.EnableRaisingEvents = $true
    
    Register-ObjectEvent -InputObject $watcher -EventName Changed -Action $OnChange
}
```

## 6. 総合的な推奨改善策

### 優先度：高
1. **共通モジュール化**: 重複コードの排除
2. **セキュリティ強化**: パスワード暗号化、メールアドレス検証
3. **プロセス監視**: 異常終了時のロックファイル対応

### 優先度：中
1. **エラー分類**: SMTP送信エラーの詳細分類
2. **設定検証**: INI設定値の妥当性チェック
3. **ログ改善**: 構造化ログの導入

### 優先度：低
1. **動的設定**: 設定ファイルの変更監視
2. **パフォーマンス**: 大量データ処理時の最適化
3. **国際化**: 多言語対応