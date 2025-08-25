# TestFramework.psm1
# PowerShellスクリプト用の軽量テストフレームワーク

$script:TestResults = @()
$script:TestCount = 0
$script:PassCount = 0
$script:FailCount = 0

function Assert-Equal {
    param($Expected, $Actual, [string]$Message = "")
    $script:TestCount++
    
    if ($Expected -eq $Actual) {
        $script:PassCount++
        Write-Host "✓ PASS: $Message" -ForegroundColor Green
        $script:TestResults += @{ Status = "PASS"; Message = $Message; Expected = $Expected; Actual = $Actual }
    } else {
        $script:FailCount++
        Write-Host "✗ FAIL: $Message" -ForegroundColor Red
        Write-Host "  Expected: $Expected" -ForegroundColor Yellow
        Write-Host "  Actual: $Actual" -ForegroundColor Yellow
        $script:TestResults += @{ Status = "FAIL"; Message = $Message; Expected = $Expected; Actual = $Actual }
    }
}

function Assert-True {
    param($Condition, [string]$Message = "")
    Assert-Equal -Expected $true -Actual $Condition -Message $Message
}

function Assert-False {
    param($Condition, [string]$Message = "")
    Assert-Equal -Expected $false -Actual $Condition -Message $Message
}

function Assert-Throws {
    param([scriptblock]$ScriptBlock, [string]$Message = "")
    $script:TestCount++
    
    try {
        & $ScriptBlock
        $script:FailCount++
        Write-Host "✗ FAIL: $Message (期待される例外が発生しませんでした)" -ForegroundColor Red
        $script:TestResults += @{ Status = "FAIL"; Message = "$Message (例外未発生)"; Expected = "Exception"; Actual = "NoException" }
    } catch {
        $script:PassCount++
        Write-Host "✓ PASS: $Message (期待される例外が発生)" -ForegroundColor Green
        $script:TestResults += @{ Status = "PASS"; Message = "$Message (例外発生)"; Expected = "Exception"; Actual = $_.Exception.Message }
    }
}

function Get-TestSummary {
    Write-Host "`n=== テスト結果サマリー ===" -ForegroundColor Cyan
    Write-Host "総テスト数: $script:TestCount" -ForegroundColor White
    Write-Host "成功: $script:PassCount" -ForegroundColor Green
    Write-Host "失敗: $script:FailCount" -ForegroundColor Red
    
    if ($script:FailCount -eq 0) {
        Write-Host "すべてのテストが成功しました！" -ForegroundColor Green
    } else {
        Write-Host "失敗したテストがあります。詳細を確認してください。" -ForegroundColor Red
    }
    
    return @{
        Total = $script:TestCount
        Pass = $script:PassCount
        Fail = $script:FailCount
        Results = $script:TestResults
    }
}

function Reset-TestCounters {
    $script:TestResults = @()
    $script:TestCount = 0
    $script:PassCount = 0
    $script:FailCount = 0
}

Export-ModuleMember -Function Assert-Equal, Assert-True, Assert-False, Assert-Throws, Get-TestSummary, Reset-TestCounters