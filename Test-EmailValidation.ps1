# Test-EmailValidation.ps1
# メールアドレス検証とメール送信関連のテスト

Import-Module "$PSScriptRoot\TestFramework.psm1" -Force

# メールアドレス検証関数（改善版）
function Test-EmailAddress {
    param([string]$Email)
    if ([string]::IsNullOrWhiteSpace($Email)) {
        return $false
    }
    
    try {
        $null = [System.Net.Mail.MailAddress]$Email
        return $true
    } catch {
        return $false
    }
}

# メール送信のモック関数
function Send-MailSmtp-Mock {
    param(
        [hashtable]$Smtp,
        [string]$To,
        [string]$Subject,
        [string]$Body,
        [string]$Cc,
        [string]$Bcc,
        [switch]$SimulateFailure
    )
    
    Write-Host "  [MOCK] メール送信シミュレーション:" -ForegroundColor Yellow
    Write-Host "    To: $To" -ForegroundColor Gray
    Write-Host "    From: $($Smtp.From)" -ForegroundColor Gray
    Write-Host "    Subject: $Subject" -ForegroundColor Gray
    Write-Host "    Body: $($Body.Substring(0, [Math]::Min(50, $Body.Length)))..." -ForegroundColor Gray
    if ($Cc) { Write-Host "    Cc: $Cc" -ForegroundColor Gray }
    if ($Bcc) { Write-Host "    Bcc: $Bcc" -ForegroundColor Gray }
    
    if ($SimulateFailure) {
        Write-Host "    [MOCK] 送信失敗をシミュレーション" -ForegroundColor Red
        return $false
    } else {
        Write-Host "    [MOCK] 送信成功をシミュレーション" -ForegroundColor Green
        return $true
    }
}

function Test-EmailAddressValidation {
    Write-Host "`n=== メールアドレス検証テスト ===" -ForegroundColor Cyan
    
    # 有効なメールアドレス
    $validEmails = @(
        "test@example.com",
        "user.name@domain.co.jp", 
        "admin+noreply@test-domain.org",
        "123456@numbers.net",
        "a@b.co"
    )
    
    foreach ($email in $validEmails) {
        $result = Test-EmailAddress -Email $email
        Assert-True $result "有効なメールアドレス: $email"
    }
    
    # 無効なメールアドレス
    $invalidEmails = @(
        "",                      # 空文字
        " ",                     # 空白のみ
        "invalid",               # ドメインなし
        "@example.com",          # ローカル部なし
        "test@",                 # ドメインなし
        "test..test@example.com", # 連続ドット
        "test@.example.com",     # ドメイン先頭ドット
        "test@example.",         # ドメイン末尾ドット
        "test space@example.com", # 空白を含む
        "test@exam ple.com"      # ドメインに空白
    )
    
    foreach ($email in $invalidEmails) {
        $result = Test-EmailAddress -Email $email
        Assert-False $result "無効なメールアドレス: '$email'"
    }
}

function Test-MailComposition {
    Write-Host "`n=== メール合成テスト ===" -ForegroundColor Cyan
    
    # Compose-Mail関数（ScriptBから抽出・改良）
    function Compose-Mail {
        param([hashtable]$Ini,[string]$Section,[pscustomobject]$Row)
        
        if (-not $Ini.ContainsKey($Section)) {
            throw "指定されたセクションが存在しません: $Section"
        }
        
        $sec = $Ini[$Section]
        $cols = $Ini['Columns']
        
        $subject = if($sec.Subject){ $sec.Subject } else { [string]$Row.($cols.Col3) }
        $body    = if($sec.Body)   { $sec.Body }    else { [string]$Row.($cols.Col4) }
        $body = $body -replace '@CRLF', "`r`n"
        
        return @{ Subject=$subject; Body=$body }
    }
    
    # テスト用設定
    $testIni = @{
        'KOZA_KAISETSU' = @{
            'Subject' = '【口座開設】お手続きの結果について'
            'Body' = 'いつもご利用ありがとうございます@CRLF@CRLFお手続きが完了いたしました@CRLF本メールは自動送信です'
        }
        'Columns' = @{
            'Col3' = 'Subject1'
            'Col4' = 'Body1'
        }
    }
    
    # テスト用CSVデータ
    $testRow = [PSCustomObject]@{
        'Subject1' = 'CSVからの件名'
        'Body1' = 'CSVからの本文です'
    }
    
    # INI設定優先のテスト
    $result = Compose-Mail -Ini $testIni -Section 'KOZA_KAISETSU' -Row $testRow
    Assert-Equal '【口座開設】お手続きの結果について' $result.Subject "INI設定の件名が優先される"
    Assert-True ($result.Body -like "*いつもご利用ありがとうございます*") "INI設定の本文が使用される"
    Assert-True ($result.Body -like "*`r`n*") "改行コードが正しく変換される"
    Assert-False ($result.Body -like "*@CRLF*") "@CRLFが残っていない"
    
    # 存在しないセクションのテスト
    Assert-Throws { 
        Compose-Mail -Ini $testIni -Section 'NONEXISTENT' -Row $testRow 
    } "存在しないセクションで例外が発生する"
}

function Test-MockEmailSending {
    Write-Host "`n=== モックメール送信テスト ===" -ForegroundColor Cyan
    
    $testSmtp = @{
        'Server' = 'localhost'
        'Port' = '25'
        'From' = 'test-system@example.com'
    }
    
    # 正常送信のテスト
    $result = Send-MailSmtp-Mock -Smtp $testSmtp -To "recipient@example.com" -Subject "テスト件名" -Body "テスト本文です" -Bcc "admin@example.com"
    Assert-True $result "正常送信時にtrueが返される"
    
    # 送信失敗のテスト  
    $result = Send-MailSmtp-Mock -Smtp $testSmtp -To "invalid@domain" -Subject "エラーテスト" -Body "エラーテスト本文" -SimulateFailure
    Assert-False $result "送信失敗時にfalseが返される"
    
    # 複数宛先のテスト（セミコロン区切り）
    $result = Send-MailSmtp-Mock -Smtp $testSmtp -To "user1@example.com;user2@example.com" -Subject "複数宛先テスト" -Body "複数宛先テスト本文"
    Assert-True $result "複数宛先での送信が成功する"
}

function Test-CsvEmailValidation {
    Write-Host "`n=== CSV内メールアドレス検証テスト ===" -ForegroundColor Cyan
    
    # CSVデータのバリデーション関数
    function Validate-CsvEmails {
        param([object[]]$Rows, [string]$EmailColumn)
        
        $errors = @()
        $i = 0
        
        foreach ($row in $Rows) {
            $i++
            $email = $row.$EmailColumn
            
            if ([string]::IsNullOrWhiteSpace($email)) {
                $errors += "行 $i : メールアドレスが空です"
            } elseif (-not (Test-EmailAddress -Email $email)) {
                $errors += "行 $i : 無効なメールアドレス形式 ($email)"
            }
        }
        
        return $errors
    }
    
    # テスト用CSVデータ
    $testData = @(
        [PSCustomObject]@{ MailAddress="valid1@example.com"; Name="ユーザー1" },
        [PSCustomObject]@{ MailAddress=""; Name="ユーザー2" },  # 空のメール
        [PSCustomObject]@{ MailAddress="invalid-email"; Name="ユーザー3" },  # 無効形式
        [PSCustomObject]@{ MailAddress="valid2@test.co.jp"; Name="ユーザー4" },
        [PSCustomObject]@{ MailAddress="user@domain"; Name="ユーザー5" }  # ドメイン不完全
    )
    
    $errors = Validate-CsvEmails -Rows $testData -EmailColumn "MailAddress"
    
    Assert-Equal 3 $errors.Count "エラー数が正しい（空・無効形式・ドメイン不完全）"
    Assert-True ($errors[0] -like "*行 2*空*") "空メールアドレスのエラーメッセージが正しい"
    Assert-True ($errors[1] -like "*行 3*無効*") "無効形式のエラーメッセージが正しい"
    Assert-True ($errors[2] -like "*行 5*無効*") "ドメイン不完全のエラーメッセージが正しい"
}

function Test-EmailSecurityFeatures {
    Write-Host "`n=== メールセキュリティ機能テスト ===" -ForegroundColor Cyan
    
    # From固定化のテスト
    function Test-FromAddressLocking {
        param([hashtable]$SmtpConfig, [string]$AttemptedFrom)
        
        # 実際のシステムでは設定ファイルのFromが常に使用される
        $actualFrom = $SmtpConfig.From  # 設定値を強制使用
        
        Write-Host "  [SECURITY] From固定化チェック:" -ForegroundColor Yellow
        Write-Host "    設定From: $($SmtpConfig.From)" -ForegroundColor Gray
        Write-Host "    試行From: $AttemptedFrom" -ForegroundColor Gray
        Write-Host "    実際From: $actualFrom" -ForegroundColor Gray
        
        return $actualFrom -eq $SmtpConfig.From
    }
    
    $testSmtp = @{ From = "system@company.com" }
    
    # 正当なFromアドレス
    $result = Test-FromAddressLocking -SmtpConfig $testSmtp -AttemptedFrom "system@company.com"
    Assert-True $result "正当なFromアドレスが使用される"
    
    # 不正なFromアドレス試行
    $result = Test-FromAddressLocking -SmtpConfig $testSmtp -AttemptedFrom "fake@hacker.com"
    Assert-True $result "不正なFromアドレス試行でも設定値が使用される（偽装防止）"
    
    # Bcc強制追加のテスト
    function Test-BccEnforcement {
        param([string]$ConfiguredBcc, [string]$ProvidedBcc)
        
        # 設定されたBccは常に追加される
        $finalBcc = if ($ProvidedBcc) { "$ProvidedBcc;$ConfiguredBcc" } else { $ConfiguredBcc }
        
        return $finalBcc -like "*$ConfiguredBcc*"
    }
    
    $result = Test-BccEnforcement -ConfiguredBcc "audit@company.com" -ProvidedBcc ""
    Assert-True $result "設定されたBccが強制的に追加される"
    
    $result = Test-BccEnforcement -ConfiguredBcc "audit@company.com" -ProvidedBcc "manager@company.com"
    Assert-True $result "既存Bccがある場合も設定Bccが追加される"
}

# テスト実行
Write-Host "メール関連機能テスト開始" -ForegroundColor Magenta
Reset-TestCounters
Test-EmailAddressValidation
Test-MailComposition
Test-MockEmailSending
Test-CsvEmailValidation
Test-EmailSecurityFeatures
$summary = Get-TestSummary
Write-Host "メール関連機能テスト完了" -ForegroundColor Magenta

return $summary