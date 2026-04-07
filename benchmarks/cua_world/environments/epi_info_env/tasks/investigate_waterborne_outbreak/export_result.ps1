# Export: investigate_waterborne_outbreak

. "C:\workspace\scripts\task_utils.ps1"

Write-Host "=== Exporting investigate_waterborne_outbreak Result ==="

$resultPath  = "C:\Users\Docker\investigate_waterborne_outbreak_result.json"
$startTsFile = "C:\Users\Docker\task_start_ts_waterborne.txt"

$taskStart = 0
if (Test-Path $startTsFile) {
    $taskStart = [int](Get-Content $startTsFile -Raw).Trim()
}
Write-Host "Task start timestamp: $taskStart"

function Get-FileResult {
    param([string]$FilePath, [bool]$ReadContent = $false, [int]$MaxLen = 10000)
    if (Test-Path $FilePath) {
        $fi    = Get-Item $FilePath
        $mtime = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
        $content = ""
        if ($ReadContent) {
            try {
                $raw = [System.IO.File]::ReadAllText($FilePath)
                $content = if ($raw.Length -gt $MaxLen) { $raw.Substring(0, $MaxLen) } else { $raw }
            } catch {}
        }
        return @{
            exists     = $true
            size_bytes = [long]$fi.Length
            mtime_unix = $mtime
            is_new     = ($mtime -gt $taskStart)
            content    = $content
        }
    }
    return @{ exists = $false; size_bytes = 0; mtime_unix = 0; is_new = $false; content = "" }
}

# Collect the investigation report
$reportResult = Get-FileResult "C:\Users\Docker\Documents\outbreak_report.txt" -ReadContent $true -MaxLen 10000

# Also check for HTML analysis output (if agent used ROUTEOUT)
$htmlPath = "C:\Users\Docker\Documents\outbreak_analysis.html"
if (-not (Test-Path $htmlPath)) { $htmlPath = "C:\Users\Docker\Documents\outbreak_analysis.htm" }
if (-not (Test-Path $htmlPath)) { $htmlPath = "C:\Users\Docker\Documents\outbreak_report.html" }
if (-not (Test-Path $htmlPath)) { $htmlPath = "C:\Users\Docker\Documents\outbreak_report.htm" }
$htmlResult = Get-FileResult $htmlPath -ReadContent $true -MaxLen 50000

$reportLower = $reportResult.content.ToLower()

# Check for key findings in the report
$hasNorth           = $reportLower.Contains("north")
$hasMunicipal       = $reportLower.Contains("municipal") -or $reportLower.Contains("tap water") -or $reportLower.Contains("water source")
$hasSwimming        = $reportLower.Contains("swim") -or $reportLower.Contains("pool")
$hasConfounder      = $reportLower.Contains("confound") -or $reportLower.Contains("not significant") -or $reportLower.Contains("no longer significant") -or $reportLower.Contains("lost significance")
$hasAttackRate      = $reportLower -match "\d+\.?\d*\s*%"
$hasRiskRatio       = $reportLower.Contains("risk ratio") -or $reportLower.Contains("rr") -or $reportLower.Contains("relative risk")
$hasOddsRatio       = $reportLower.Contains("odds ratio") -or $reportLower.Contains(" or ") -or $reportLower.Contains("adjusted")
$hasDoseResponse    = ($reportLower.Contains("dose") -or $reportLower.Contains("glasses") -or $reportLower.Contains("consumption")) -and ($reportLower.Contains("significant") -or $reportLower.Contains("trend") -or $reportLower.Contains("relationship") -or $reportLower.Contains("response"))
$hasFilter          = $reportLower.Contains("filter") -and ($reportLower.Contains("protect") -or $reportLower.Contains("lower") -or $reportLower.Contains("reduc"))

$result = [ordered]@{
    task        = "investigate_waterborne_outbreak"
    task_start  = $taskStart
    report = @{
        exists           = $reportResult.exists
        size_bytes       = $reportResult.size_bytes
        mtime_unix       = $reportResult.mtime_unix
        is_new           = $reportResult.is_new
        content          = $reportResult.content
        has_north        = $hasNorth
        has_municipal    = $hasMunicipal
        has_swimming     = $hasSwimming
        has_confounder   = $hasConfounder
        has_attack_rate  = $hasAttackRate
        has_risk_ratio   = $hasRiskRatio
        has_odds_ratio   = $hasOddsRatio
        has_dose_response = $hasDoseResponse
        has_filter       = $hasFilter
    }
    html_output = @{
        exists     = $htmlResult.exists
        size_bytes = $htmlResult.size_bytes
        mtime_unix = $htmlResult.mtime_unix
        is_new     = $htmlResult.is_new
    }
}

$result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
Write-Host "=== Export Complete ==="
