$ErrorActionPreference = "Continue"

Write-Host "=== Exporting backtest_strategy_and_export result ==="

$outputDir = "C:\Users\Docker\Desktop\NinjaTraderTasks"
$expectedOutput = Join-Path $outputDir "spy_backtest_trades.csv"

# Check if the expected output file exists
$fileExists = Test-Path $expectedOutput
$fileSize = 0
$lineCount = 0
$hasSPY = $false
$hasBuyEntries = $false
$hasSellEntries = $false
$hasDateRange = $false
$headerLine = ""
$sampleLines = @()

if ($fileExists) {
    $fileInfo = Get-Item $expectedOutput
    $fileSize = $fileInfo.Length

    try {
        $lines = Get-Content $expectedOutput -ErrorAction SilentlyContinue
        $lineCount = $lines.Count

        if ($lineCount -gt 0) {
            $headerLine = $lines[0]

            # Get first 10 lines as sample
            $sampleLines = $lines | Select-Object -First 10

            # Search file content for indicators
            $fullContent = $lines -join "`n"
            $contentLower = $fullContent.ToLower()

            if ($contentLower -match "spy") { $hasSPY = $true }
            if ($contentLower -match "buy|long|entry") { $hasBuyEntries = $true }
            if ($contentLower -match "sell|short|exit") { $hasSellEntries = $true }
            if ($contentLower -match "2023|2024") { $hasDateRange = $true }
        }
    } catch {
        Write-Host "WARNING: Could not read export file: $($_.Exception.Message)"
    }
}

# Also check for alternative export locations the agent might have used
$altPaths = @(
    "C:\Users\Docker\Desktop\spy_backtest_trades.csv",
    "C:\Users\Docker\Documents\spy_backtest_trades.csv",
    "C:\Users\Docker\Desktop\NinjaTraderTasks\spy_backtest_trades.txt"
)
$altFileFound = $false
$altFilePath = ""
foreach ($alt in $altPaths) {
    if (Test-Path $alt) {
        $altFileFound = $true
        $altFilePath = $alt
        break
    }
}

# Create result JSON
$result = @{
    file_exists = $fileExists
    file_size = $fileSize
    line_count = $lineCount
    has_spy = $hasSPY
    has_buy_entries = $hasBuyEntries
    has_sell_entries = $hasSellEntries
    has_date_range = $hasDateRange
    header_line = $headerLine
    sample_lines = ($sampleLines -join "`n")
    alt_file_found = $altFileFound
    alt_file_path = $altFilePath
    export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
}

$resultPath = Join-Path $outputDir "backtest_strategy_and_export_result.json"
$result | ConvertTo-Json -Depth 5 | Out-File $resultPath -Encoding utf8
Write-Host "Result saved to: $resultPath"

Write-Host "=== Export Complete ==="
