$ErrorActionPreference = "Continue"

Write-Host "=== Exporting dual_chart_technical_setup result ==="

$outputDir = "C:\Users\Docker\Desktop\NinjaTraderTasks"
$ntDocDir = "C:\Users\Docker\Documents\NinjaTrader 8"
$wsDir = Join-Path $ntDocDir "workspaces"

# Read baseline
$baselinePath = Join-Path $outputDir "dual_chart_baseline.json"
$baseline = @{ workspace_files = @() }
if (Test-Path $baselinePath) {
    try {
        $baseline = Get-Content $baselinePath -Raw | ConvertFrom-Json
    } catch { }
}

# Check current workspace state
$workspaceModified = $false
$workspaceContent = ""
$workspaceSize = 0

if (Test-Path $wsDir) {
    Get-ChildItem $wsDir -Filter "*.xml" -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -ne "_Workspaces.xml"
    } | ForEach-Object {
        $currentFile = $_
        try {
            $content = Get-Content $currentFile.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -and $content.Length -gt $workspaceContent.Length) {
                $workspaceContent = $content
                $workspaceSize = $currentFile.Length
            }
        } catch { }

        # Check for modification against baseline
        $baseMatch = $null
        if ($baseline.workspace_files) {
            $baseMatch = $baseline.workspace_files | Where-Object { $_.name -eq $currentFile.Name }
        }
        if ($baseMatch) {
            if ($currentFile.Length -ne $baseMatch.size -or $currentFile.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") -ne $baseMatch.modified) {
                $workspaceModified = $true
            }
        } else {
            $workspaceModified = $true
        }
    }
}

# Analyze workspace XML for chart configurations
$hasAAPL = $false
$hasMSFT = $false
$hasSMA = $false
$hasEMA = $false
$hasBollinger = $false
$hasMACD = $false
$hasVolume = $false
$chartCount = 0

if ($workspaceContent) {
    if ($workspaceContent -match "(?i)AAPL") { $hasAAPL = $true }
    if ($workspaceContent -match "(?i)MSFT") { $hasMSFT = $true }
    if ($workspaceContent -match "(?i)SMA|SimpleMovingAverage|Simple.?Moving") { $hasSMA = $true }
    if ($workspaceContent -match "(?i)EMA|ExponentialMovingAverage|Exponential.?Moving") { $hasEMA = $true }
    if ($workspaceContent -match "(?i)Bollinger|BollingerBands") { $hasBollinger = $true }
    if ($workspaceContent -match "(?i)MACD") { $hasMACD = $true }
    if ($workspaceContent -match "(?i)Volume|VOL") { $hasVolume = $true }

    # Count chart-like elements
    $chartMatches = [regex]::Matches($workspaceContent, "(?i)ChartControl|ChartTab|<Chart[ >]")
    $chartCount = $chartMatches.Count
}

# Create result JSON
$result = @{
    workspace_modified = $workspaceModified
    workspace_size = $workspaceSize
    has_aapl = $hasAAPL
    has_msft = $hasMSFT
    has_sma = $hasSMA
    has_ema = $hasEMA
    has_bollinger = $hasBollinger
    has_macd = $hasMACD
    has_volume = $hasVolume
    chart_count = $chartCount
    both_instruments = ($hasAAPL -and $hasMSFT)
    export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
}

$resultPath = Join-Path $outputDir "dual_chart_technical_setup_result.json"
$result | ConvertTo-Json -Depth 5 | Out-File $resultPath -Encoding utf8
Write-Host "Result saved to: $resultPath"

Write-Host "=== Export Complete ==="
