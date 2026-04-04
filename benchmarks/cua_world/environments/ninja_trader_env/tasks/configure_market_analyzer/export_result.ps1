$ErrorActionPreference = "Continue"

Write-Host "=== Exporting configure_market_analyzer result ==="

$outputDir = "C:\Users\Docker\Desktop\NinjaTraderTasks"
$ntDocDir = "C:\Users\Docker\Documents\NinjaTrader 8"
$wsDir = Join-Path $ntDocDir "workspaces"

# Read baseline
$baselinePath = Join-Path $outputDir "market_analyzer_baseline.json"
$baseline = @{ workspace_files = @() }
if (Test-Path $baselinePath) {
    try {
        $baseline = Get-Content $baselinePath -Raw | ConvertFrom-Json
    } catch {
        Write-Host "WARNING: Could not parse baseline JSON"
    }
}

# Check current workspace state
$workspaceModified = $false
$workspaceContent = ""
$workspaceSize = 0
$currentWorkspaceFiles = @()

if (Test-Path $wsDir) {
    Get-ChildItem $wsDir -Filter "*.xml" -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -ne "_Workspaces.xml"
    } | ForEach-Object {
        $currentWorkspaceFiles += @{
            name = $_.Name
            size = $_.Length
            modified = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        }

        # Read the workspace content for analysis
        try {
            $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -and $content.Length -gt $workspaceContent.Length) {
                $workspaceContent = $content
                $workspaceSize = $_.Length
            }
        } catch { }
    }
}

# Check if workspace was modified compared to baseline
$baselineNames = @()
if ($baseline.workspace_files) {
    $baseline.workspace_files | ForEach-Object { $baselineNames += $_.name }
}
$currentNames = @()
$currentWorkspaceFiles | ForEach-Object { $currentNames += $_.name }

# New files or size changes indicate modification
if ($currentNames.Count -gt $baselineNames.Count) {
    $workspaceModified = $true
} else {
    foreach ($curr in $currentWorkspaceFiles) {
        $baseMatch = $baseline.workspace_files | Where-Object { $_.name -eq $curr.name }
        if ($baseMatch -and $curr.size -ne $baseMatch.size) {
            $workspaceModified = $true
            break
        }
        if ($baseMatch -and $curr.modified -ne $baseMatch.modified) {
            $workspaceModified = $true
            break
        }
    }
}

# Analyze workspace XML for Market Analyzer indicators
$hasMarketAnalyzer = $false
$hasSPY = $false
$hasAAPL = $false
$hasMSFT = $false
$hasRSI = $false
$hasLast = $false
$hasNetChange = $false
$instrumentCount = 0

if ($workspaceContent) {
    # Search for Market Analyzer patterns in the XML
    if ($workspaceContent -match "(?i)MarketAnalyzer|Market_Analyzer|MarketAnalyzerControl") {
        $hasMarketAnalyzer = $true
    }
    if ($workspaceContent -match "(?i)SPY") { $hasSPY = $true }
    if ($workspaceContent -match "(?i)AAPL") { $hasAAPL = $true }
    if ($workspaceContent -match "(?i)MSFT") { $hasMSFT = $true }
    if ($workspaceContent -match "(?i)\bRSI\b|RelativeStrengthIndex|Relative.?Strength") { $hasRSI = $true }
    if ($workspaceContent -match "(?i)Last|LastPrice|last_price") { $hasLast = $true }
    if ($workspaceContent -match "(?i)NetChange|Net.?Change|net_change|NetChg") { $hasNetChange = $true }

    $instrumentCount = 0
    if ($hasSPY) { $instrumentCount++ }
    if ($hasAAPL) { $instrumentCount++ }
    if ($hasMSFT) { $instrumentCount++ }
}

# Create result JSON
$result = @{
    workspace_modified = $workspaceModified
    workspace_size = $workspaceSize
    workspace_file_count = $currentWorkspaceFiles.Count
    has_market_analyzer = $hasMarketAnalyzer
    has_spy = $hasSPY
    has_aapl = $hasAAPL
    has_msft = $hasMSFT
    instrument_count = $instrumentCount
    has_rsi = $hasRSI
    has_last = $hasLast
    has_net_change = $hasNetChange
    export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
}

$resultPath = Join-Path $outputDir "configure_market_analyzer_result.json"
$result | ConvertTo-Json -Depth 5 | Out-File $resultPath -Encoding utf8
Write-Host "Result saved to: $resultPath"

Write-Host "=== Export Complete ==="
