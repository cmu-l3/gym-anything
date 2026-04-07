$ErrorActionPreference = "Continue"

Write-Host "=== Exporting strategy_optimization_validated_deployment result ==="

$outputDir = "C:\Users\Docker\Desktop\NinjaTraderTasks"

# ---- Check qualification_report.txt ----
$reportPath = Join-Path $outputDir "qualification_report.txt"
$reportExists = Test-Path $reportPath
$reportContent = ""
$reportFastValue = ""
$reportSlowValue = ""
$reportNetProfit = ""
$reportMaxDrawdown = ""
$reportFormatValid = $false

if ($reportExists) {
    try {
        $reportContent = Get-Content $reportPath -Raw -ErrorAction SilentlyContinue
        if ($reportContent) {
            $reportContent = $reportContent.Trim()

            # Extract Fast value
            if ($reportContent -match "Fast\s*=\s*(\d+)") {
                $reportFastValue = $Matches[1]
            }
            # Extract Slow value
            if ($reportContent -match "Slow\s*=\s*(\d+)") {
                $reportSlowValue = $Matches[1]
            }
            # Extract NetProfit value (may include negative, decimals, commas)
            if ($reportContent -match "NetProfit\s*=\s*([0-9,.\-\$]+)") {
                $reportNetProfit = $Matches[1]
            }
            # Extract MaxDrawdown value
            if ($reportContent -match "MaxDrawdown\s*=\s*([0-9,.\-\$]+)") {
                $reportMaxDrawdown = $Matches[1]
            }

            # Format valid if all four fields found
            if ($reportFastValue -and $reportSlowValue -and $reportNetProfit -and $reportMaxDrawdown) {
                $reportFormatValid = $true
            }
        }
    } catch {
        Write-Host "WARNING: Could not read report file: $($_.Exception.Message)"
    }
}

# Check alternative report locations
$altReportPaths = @(
    "C:\Users\Docker\Desktop\qualification_report.txt",
    "C:\Users\Docker\Documents\qualification_report.txt",
    "C:\Users\Docker\Desktop\NinjaTraderTasks\qualification_report.csv"
)
$altReportFound = $false
$altReportPath = ""
foreach ($alt in $altReportPaths) {
    if (Test-Path $alt) {
        $altReportFound = $true
        $altReportPath = $alt
        break
    }
}

# ---- Check qualified_trades.csv ----
$csvPath = Join-Path $outputDir "qualified_trades.csv"
$csvExists = Test-Path $csvPath
$csvFileSize = 0
$csvLineCount = 0
$csvHasSPY = $false
$csvHasBuyEntries = $false
$csvHasSellEntries = $false
$csvHasDateRange = $false
$csvHeaderLine = ""
$csvSampleLines = @()

if ($csvExists) {
    $csvInfo = Get-Item $csvPath
    $csvFileSize = $csvInfo.Length

    try {
        $lines = Get-Content $csvPath -ErrorAction SilentlyContinue
        $csvLineCount = $lines.Count

        if ($csvLineCount -gt 0) {
            $csvHeaderLine = $lines[0]
            $csvSampleLines = $lines | Select-Object -First 10

            $fullContent = $lines -join "`n"
            $contentLower = $fullContent.ToLower()

            if ($contentLower -match "spy") { $csvHasSPY = $true }
            if ($contentLower -match "buy|long|entry") { $csvHasBuyEntries = $true }
            if ($contentLower -match "sell|short|exit") { $csvHasSellEntries = $true }
            if ($contentLower -match "2023|2024") { $csvHasDateRange = $true }
        }
    } catch {
        Write-Host "WARNING: Could not read CSV file: $($_.Exception.Message)"
    }
}

# Check alternative CSV locations
$altCsvPaths = @(
    "C:\Users\Docker\Desktop\qualified_trades.csv",
    "C:\Users\Docker\Documents\qualified_trades.csv",
    "C:\Users\Docker\Desktop\NinjaTraderTasks\qualified_trades.txt"
)
$altCsvFound = $false
$altCsvPath = ""
foreach ($alt in $altCsvPaths) {
    if (Test-Path $alt) {
        $altCsvFound = $true
        $altCsvPath = $alt
        break
    }
}

# ---- Check workspace ----
$wsDir = "$env:USERPROFILE\Documents\NinjaTrader 8\workspaces"
$wsExists = Test-Path (Join-Path $wsDir "StrategyQualification.xml")
$wsXmlContent = ""
$wsHasStrategyAnalyzer = $false
$wsHasSampleMACross = $false
$wsHasSPY = $false
$wsSmaPeriods = @()
$wsHasRsi = $false

if ($wsExists) {
    try {
        $wsXmlContent = Get-Content (Join-Path $wsDir "StrategyQualification.xml") -Raw -ErrorAction SilentlyContinue
        if ($wsXmlContent) {
            $wsContentLower = $wsXmlContent.ToLower()
            if ($wsContentLower -match "strategyanalyzer|strategy analyzer") { $wsHasStrategyAnalyzer = $true }
            if ($wsXmlContent -match "SampleMACross") { $wsHasSampleMACross = $true }
            if ($wsXmlContent -match "SPY") { $wsHasSPY = $true }

            # Extract SMA periods from workspace XML
            $smaMatches = [regex]::Matches($wsXmlContent, "(?i)SMA.*?Period.*?(\d+)")
            foreach ($m in $smaMatches) {
                $wsSmaPeriods += $m.Groups[1].Value
            }
            $wsSmaPeriods = $wsSmaPeriods | Sort-Object -Unique

            if ($wsXmlContent -match "(?i)RSI") { $wsHasRsi = $true }
        }
    } catch {
        Write-Host "WARNING: Could not read workspace XML: $($_.Exception.Message)"
    }
}

# ---- Assemble result JSON ----
$result = @{
    # Report file checks
    report_exists              = $reportExists
    report_content             = $reportContent
    report_fast_value          = $reportFastValue
    report_slow_value          = $reportSlowValue
    report_net_profit          = $reportNetProfit
    report_max_drawdown        = $reportMaxDrawdown
    report_format_valid        = $reportFormatValid
    alt_report_found           = $altReportFound
    alt_report_path            = $altReportPath

    # CSV file checks
    csv_exists                 = $csvExists
    csv_file_size              = $csvFileSize
    csv_line_count             = $csvLineCount
    csv_has_spy                = $csvHasSPY
    csv_has_buy_entries        = $csvHasBuyEntries
    csv_has_sell_entries        = $csvHasSellEntries
    csv_has_date_range         = $csvHasDateRange
    csv_header_line            = $csvHeaderLine
    csv_sample_lines           = ($csvSampleLines -join "`n")
    alt_csv_found              = $altCsvFound
    alt_csv_path               = $altCsvPath

    # Workspace checks
    workspace_exists           = $wsExists
    ws_has_strategy_analyzer   = $wsHasStrategyAnalyzer
    ws_has_sample_ma_cross     = $wsHasSampleMACross
    ws_has_spy                 = $wsHasSPY
    ws_sma_periods             = ($wsSmaPeriods -join ",")
    ws_has_rsi                 = $wsHasRsi

    # Metadata
    export_timestamp           = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
}

$resultPath = Join-Path $outputDir "strategy_optimization_validated_deployment_result.json"
$result | ConvertTo-Json -Depth 5 | Out-File $resultPath -Encoding utf8
Write-Host "Result saved to: $resultPath"

Write-Host "=== Export Complete ==="
