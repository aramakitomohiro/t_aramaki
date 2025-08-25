# Test-GetIni.ps1
# Get-Ini関数の単体テスト

Import-Module "$PSScriptRoot\TestFramework.psm1" -Force

# テスト用のINIファイル内容を準備
$TestIniContent = @"
# テスト用INI
[General]
Confirm=true
Bcc=test@example.com

[Paths]
UserArea=C:\Test\User
LogDir=C:\Test\Logs

[SMTP]
Server=localhost
Port=25
From=test-from@example.com

[TestSection]
TestKey=TestValue
EmptyValue=
"@

# Get-Ini関数を定義（ScriptAから抽出）
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

function Test-GetIni-Normal {
    Write-Host "`n=== Get-Ini 正常テスト ===" -ForegroundColor Cyan
    
    # テスト用一時ファイル作成
    $tempIni = "/tmp/test_mailsettings.ini"
    Set-Content -Path $tempIni -Value $TestIniContent -Encoding UTF8
    
    try {
        $result = Get-Ini -Path $tempIni
        
        # 検証
        Assert-True ($result -is [hashtable]) "戻り値がハッシュテーブルである"
        Assert-True ($result.ContainsKey('General')) "Generalセクションが存在する"
        Assert-True ($result.ContainsKey('Paths')) "Pathsセクションが存在する"
        Assert-True ($result.ContainsKey('SMTP')) "SMTPセクションが存在する"
        Assert-True ($result.ContainsKey('TestSection')) "TestSectionが存在する"
        
        Assert-Equal "true" $result['General']['Confirm'] "Confirm設定が正しい"
        Assert-Equal "test@example.com" $result['General']['Bcc'] "Bcc設定が正しい"
        Assert-Equal "localhost" $result['SMTP']['Server'] "SMTPサーバー設定が正しい"
        Assert-Equal "25" $result['SMTP']['Port'] "SMTPポート設定が正しい"
        Assert-Equal "test-from@example.com" $result['SMTP']['From'] "From設定が正しい"
        Assert-Equal "TestValue" $result['TestSection']['TestKey'] "カスタムセクションの値が正しい"
        Assert-Equal "" $result['TestSection']['EmptyValue'] "空の値が正しく処理される"
        
    } finally {
        # クリーンアップ
        if (Test-Path $tempIni) { Remove-Item $tempIni -Force }
    }
}

function Test-GetIni-FileNotFound {
    Write-Host "`n=== Get-Ini ファイル未存在テスト ===" -ForegroundColor Cyan
    
    Assert-Throws { Get-Ini -Path "C:\NonExistent\file.ini" } "存在しないファイルで例外が発生する"
}

function Test-GetIni-InvalidFormat {
    Write-Host "`n=== Get-Ini 不正フォーマットテスト ===" -ForegroundColor Cyan
    
    $invalidIni = @"
# 不正なINI
[General]
Confirm=true
InvalidLine
=ValueOnly
KeyOnly=
# コメント行
[IncompleteSection
AnotherValidKey=ValidValue
"@
    
    $tempIni = "/tmp/test_invalid.ini"
    Set-Content -Path $tempIni -Value $invalidIni -Encoding UTF8
    
    try {
        $result = Get-Ini -Path $tempIni
        
        # 不正な行は無視され、有効な設定のみ読み込まれることを確認
        Assert-True ($result['General']['Confirm'] -eq 'true') "有効な設定は正しく読み込まれる"
        Assert-False ($result['General'].ContainsKey('InvalidLine')) "不正な行は無視される"
        Assert-False ($result['General'].ContainsKey('')) "空のキーは無視される"
        Assert-Equal "" $result['General']['KeyOnly'] "値のないキーは空文字として処理される"
        
    } finally {
        if (Test-Path $tempIni) { Remove-Item $tempIni -Force }
    }
}

function Test-GetIni-EmptyFile {
    Write-Host "`n=== Get-Ini 空ファイルテスト ===" -ForegroundColor Cyan
    
    $tempIni = "/tmp/test_empty.ini"
    Set-Content -Path $tempIni -Value "" -Encoding UTF8
    
    try {
        $result = Get-Ini -Path $tempIni
        
        # 空ファイルでもGeneralセクションは作成される
        Assert-True ($result -is [hashtable]) "空ファイルでもハッシュテーブルが返される"
        Assert-True ($result.ContainsKey('General')) "空ファイルでもGeneralセクションが作成される"
        Assert-Equal 0 $result['General'].Count "Generalセクションは空"
        
    } finally {
        if (Test-Path $tempIni) { Remove-Item $tempIni -Force }
    }
}

function Test-GetIni-UnicodeContent {
    Write-Host "`n=== Get-Ini Unicode文字テスト ===" -ForegroundColor Cyan
    
    $unicodeIni = @"
[General]
Japanese=こんにちは
Chinese=你好
Korean=안녕하세요
Emoji=😊📧✉️

[Paths]
日本語パス=C:\テスト\メール送信
"@
    
    $tempIni = "/tmp/test_unicode.ini"
    Set-Content -Path $tempIni -Value $unicodeIni -Encoding UTF8
    
    try {
        $result = Get-Ini -Path $tempIni
        
        Assert-Equal "こんにちは" $result['General']['Japanese'] "日本語文字が正しく読み込まれる"
        Assert-Equal "你好" $result['General']['Chinese'] "中国語文字が正しく読み込まれる"
        Assert-Equal "안녕하세요" $result['General']['Korean'] "韓国語文字が正しく読み込まれる"
        Assert-Equal "😊📧✉️" $result['General']['Emoji'] "絵文字が正しく読み込まれる"
        Assert-Equal "C:\テスト\メール送信" $result['Paths']['日本語パス'] "日本語キーとパスが正しく処理される"
        
    } finally {
        if (Test-Path $tempIni) { Remove-Item $tempIni -Force }
    }
}

# テスト実行
Write-Host "Get-Ini関数テスト開始" -ForegroundColor Magenta
Reset-TestCounters
Test-GetIni-Normal
Test-GetIni-FileNotFound
Test-GetIni-InvalidFormat
Test-GetIni-EmptyFile
Test-GetIni-UnicodeContent
$summary = Get-TestSummary
Write-Host "Get-Ini関数テスト完了" -ForegroundColor Magenta

return $summary