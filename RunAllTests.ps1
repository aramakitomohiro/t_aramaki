# RunAllTests.ps1
# メール送信スクリプトの全テストを実行

param(
    [switch]$Verbose,
    [string]$TestFilter = "*"
)

$ErrorActionPreference = 'Continue'

Write-Host "=== PowerShellメール送信スクリプト テストスイート ===" -ForegroundColor Cyan
Write-Host "開始時刻: $(Get-Date)" -ForegroundColor White
Write-Host "実行環境: PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor White

# テストスクリプトの一覧
$testScripts = @(
    @{ Name = "Test-GetIni.ps1"; Description = "INI設定ファイル読み込み機能" },
    @{ Name = "Test-EmailValidation.ps1"; Description = "メール関連機能とセキュリティ" }
)

$allResults = @()
$totalTests = 0
$totalPass = 0
$totalFail = 0

foreach ($testScript in $testScripts) {
    $scriptName = $testScript.Name
    $description = $testScript.Description
    
    if ($scriptName -like $TestFilter) {
        Write-Host "`n" + "="*60 -ForegroundColor Yellow
        Write-Host "実行中: $scriptName" -ForegroundColor Yellow
        Write-Host "説明: $description" -ForegroundColor Yellow
        Write-Host "="*60 -ForegroundColor Yellow
        
        $scriptPath = Join-Path $PSScriptRoot $scriptName
        
        if (Test-Path $scriptPath) {
            try {
                $startTime = Get-Date
                $result = & $scriptPath
                $endTime = Get-Date
                $duration = $endTime - $startTime
                
                $allResults += $result
                $totalTests += $result.Total
                $totalPass += $result.Pass
                $totalFail += $result.Fail
                
                Write-Host "`n実行時間: $($duration.TotalSeconds.ToString('F2'))秒" -ForegroundColor Gray
                
                if ($result.Fail -eq 0) {
                    Write-Host "✓ $scriptName - すべて成功 ($($result.Pass)/$($result.Total))" -ForegroundColor Green
                } else {
                    Write-Host "✗ $scriptName - $($result.Fail)件の失敗 ($($result.Pass)/$($result.Total))" -ForegroundColor Red
                    
                    if ($Verbose) {
                        Write-Host "失敗したテスト:" -ForegroundColor Red
                        $result.Results | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
                            Write-Host "  - $($_.Message)" -ForegroundColor Red
                            Write-Host "    Expected: $($_.Expected), Actual: $($_.Actual)" -ForegroundColor Yellow
                        }
                    }
                }
            } catch {
                Write-Host "✗ $scriptName - 実行エラー: $($_.Exception.Message)" -ForegroundColor Red
                if ($Verbose) {
                    Write-Host "スタックトレース:" -ForegroundColor Red
                    Write-Host $_.ScriptStackTrace -ForegroundColor Yellow
                }
                $totalFail++
            }
        } else {
            Write-Host "✗ $scriptName - ファイルが見つかりません: $scriptPath" -ForegroundColor Red
        }
    }
}

# 最終結果サマリー
Write-Host "`n" + "="*60 -ForegroundColor Cyan
Write-Host "テストスイート実行完了" -ForegroundColor Cyan
Write-Host "="*60 -ForegroundColor Cyan
Write-Host "総テスト数: $totalTests" -ForegroundColor White
Write-Host "成功: $totalPass" -ForegroundColor Green  
Write-Host "失敗: $totalFail" -ForegroundColor Red

if ($totalTests -gt 0) {
    $successRate = [Math]::Round(($totalPass / $totalTests) * 100, 1)
    Write-Host "成功率: $successRate%" -ForegroundColor White
}

Write-Host "終了時刻: $(Get-Date)" -ForegroundColor White

# テスト結果の詳細出力（失敗がある場合）
if ($totalFail -gt 0 -and $Verbose) {
    Write-Host "`n=== 失敗したテストの詳細 ===" -ForegroundColor Red
    foreach ($result in $allResults) {
        $failedTests = $result.Results | Where-Object { $_.Status -eq "FAIL" }
        if ($failedTests.Count -gt 0) {
            foreach ($failed in $failedTests) {
                Write-Host "❌ $($failed.Message)" -ForegroundColor Red
                Write-Host "   期待値: $($failed.Expected)" -ForegroundColor Yellow
                Write-Host "   実際値: $($failed.Actual)" -ForegroundColor Yellow
                Write-Host ""
            }
        }
    }
}

# 推奨事項の表示
Write-Host "`n=== テスト実行ガイド ===" -ForegroundColor Cyan
Write-Host "• すべてのテストを詳細モードで実行: .\RunAllTests.ps1 -Verbose" -ForegroundColor White
Write-Host "• 特定のテストのみ実行: .\RunAllTests.ps1 -TestFilter '*GetIni*'" -ForegroundColor White
Write-Host "• 実際のメール送信は行われません（モック使用）" -ForegroundColor Green
Write-Host "• テスト環境では外部ネットワーク接続不要" -ForegroundColor Green

if ($totalFail -eq 0) {
    Write-Host "`n🎉 すべてのテストが成功しました！" -ForegroundColor Green
    Write-Host "スクリプトは本番環境での使用準備が整っています。" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n❌ 失敗したテストがあります。" -ForegroundColor Red
    Write-Host "詳細は -Verbose オプションで確認できます。" -ForegroundColor Red
    Write-Host "修正後に再テストを実行してください。" -ForegroundColor Red
    exit 1
}