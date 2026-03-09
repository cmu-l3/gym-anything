<#
  export_result.ps1 - PortfolioAnalytics risk engine result export
  Reads the three calculator source files, builds the project, and writes result JSON.
#>

. "C:\workspace\scripts\task_utils.ps1"

$SrcDir     = "C:\Users\Docker\source\repos\PortfolioAnalytics\src\PortfolioAnalytics"
$ResultPath = "C:\Users\Docker\portfolio_risk_engine_result.json"
$TsFile     = "C:\Users\Docker\portfolio_risk_engine_start_ts.txt"

Write-Host "=== Exporting portfolio_risk_engine result ==="

# ── 1. Kill VS to flush any unsaved in-memory edits ──────────────────────────
Kill-AllVS2022
Start-Sleep -Seconds 3

# ── 2. Read task start timestamp ──────────────────────────────────────────────
$taskStart = 0
if (Test-Path $TsFile) {
    $taskStart = [int](Get-Content $TsFile -Raw).Trim()
}

# ── 3. Read each calculator source file ───────────────────────────────────────
function Read-SourceFile($path) {
    if (Test-Path $path) {
        return (Get-Content $path -Raw -Encoding UTF8)
    }
    return ""
}

$varSrc    = Read-SourceFile "$SrcDir\VaRCalculator.cs"
$sharpeSrc = Read-SourceFile "$SrcDir\SharpeRatioCalculator.cs"
$mddSrc    = Read-SourceFile "$SrcDir\MaxDrawdownCalculator.cs"

# ── 4. Check modification times ───────────────────────────────────────────────
function Was-Modified($path, $since) {
    if (-not (Test-Path $path)) { return $false }
    $mtime = [int][DateTimeOffset]::new((Get-Item $path).LastWriteTimeUtc).ToUnixTimeSeconds()
    return $mtime -gt $since
}

$varModified    = Was-Modified "$SrcDir\VaRCalculator.cs"    $taskStart
$sharpeModified = Was-Modified "$SrcDir\SharpeRatioCalculator.cs" $taskStart
$mddModified    = Was-Modified "$SrcDir\MaxDrawdownCalculator.cs"  $taskStart
$anyModified    = $varModified -or $sharpeModified -or $mddModified

# ── 5. Static analysis: detect stub ("return 0.0;" only, no real logic) ───────
function Is-Stub($src) {
    # A stub returns 0.0 and has no meaningful logic tokens
    $hasSort    = $src -match "Sort\s*\("
    $hasLinq    = $src -match "\.(Average|Sum|Min|Max|OrderBy)\s*\("
    $hasMath    = $src -match "Math\.(Sqrt|Abs|Log|Pow)\s*\("
    $hasLoop    = $src -match "\bfor\b|\bforeach\b|\bwhile\b"
    $hasSqrt    = $src -match "Sqrt\s*\(\s*252"
    return -not ($hasSort -or $hasLinq -or $hasMath -or $hasLoop -or $hasSqrt)
}

$varIsStub    = Is-Stub $varSrc
$sharpeIsStub = Is-Stub $sharpeSrc
$mddIsStub    = Is-Stub $mddSrc

# ── 6. Detect specific algorithm patterns ─────────────────────────────────────
# VaR: needs Sort + percentile index
$varHasSort       = $varSrc -match "\.Sort\s*\("
$varHasPercentile = $varSrc -match "0\.05|floor|Floor|percentile|Percentile"
$varHasNegate     = $varSrc -match "\-\s*sorted|\-\s*returns|-dailyReturns|-returns\[|return\s+-"

# Sharpe: needs sqrt(252), mean, std dev
$sharpeHasSqrt252   = $sharpeSrc -match "Sqrt\s*\(\s*252|252.*Sqrt|sqrt.*252"
$sharpeHasMean      = $sharpeSrc -match "Average\s*\(|Sum.*Count|mean|Mean"
$sharpeHasStdDev    = $sharpeSrc -match "stddev|StdDev|variance|Variance|stdev|Math\.Sqrt"
$sharpeHasRiskFree  = $sharpeSrc -match "risk_free|riskFree|rf_daily|rfDaily|252"

# MaxDrawdown: needs peak tracking and drawdown fraction
$mddHasPeak      = $mddSrc -match "\bpeak\b|\bPeak\b|running.*max|highWater"
$mddHasDrawdown  = $mddSrc -match "drawdown|DrawDown|maxDD"
$mddHasFraction  = $mddSrc -match "peak\s*-|peak\s*>\s*0|/ peak|/\s*peak"

# ── 7. Build the project ──────────────────────────────────────────────────────
$dotnet = Find-DotnetExe
$buildOutput = & $dotnet build "$SrcDir\PortfolioAnalytics.csproj" --configuration Release 2>&1
$buildStr     = $buildOutput -join "`n"
$buildSuccess = $buildStr -match "Build succeeded"
$errorMatch   = [regex]::Match($buildStr, "(\d+)\s+Error\(s\)")
$buildErrors  = if ($errorMatch.Success) { [int]$errorMatch.Groups[1].Value } else { 0 }
if (-not $buildSuccess) { $buildErrors = [Math]::Max($buildErrors, 1) }

Write-Host "Build success: $buildSuccess  Errors: $buildErrors"

# ── 8. Write result JSON ──────────────────────────────────────────────────────
$result = [ordered]@{
    task_start        = $taskStart
    any_file_modified = $anyModified
    var_modified      = $varModified
    sharpe_modified   = $sharpeModified
    mdd_modified      = $mddModified
    var_is_stub       = $varIsStub
    sharpe_is_stub    = $sharpeIsStub
    mdd_is_stub       = $mddIsStub
    var_has_sort      = $varHasSort
    var_has_percentile = $varHasPercentile
    var_has_negate    = $varHasNegate
    sharpe_has_sqrt252  = $sharpeHasSqrt252
    sharpe_has_mean     = $sharpeHasMean
    sharpe_has_stddev   = $sharpeHasStdDev
    sharpe_has_riskfree = $sharpeHasRiskFree
    mdd_has_peak      = $mddHasPeak
    mdd_has_drawdown  = $mddHasDrawdown
    mdd_has_fraction  = $mddHasFraction
    build_success     = [bool]$buildSuccess
    build_errors      = $buildErrors
}

$result | ConvertTo-Json -Depth 5 | Set-Content $ResultPath -Encoding UTF8

Write-Host "Result written to $ResultPath"
Write-Host "=== Export complete ==="
