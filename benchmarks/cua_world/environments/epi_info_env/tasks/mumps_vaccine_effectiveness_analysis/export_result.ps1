# Export: mumps_vaccine_effectiveness_analysis
# Reads task start timestamp and checks output files created by the agent

. "C:\workspace\scripts\task_utils.ps1"

Write-Host "=== Exporting mumps_vaccine_effectiveness_analysis Result ==="

$resultPath  = "C:\Users\Docker\mumps_vaccine_effectiveness_analysis_result.json"
$startTsFile = "C:\Users\Docker\task_start_ts_mumps_ve.txt"

$taskStart = 0
if (Test-Path $startTsFile) {
    $taskStart = [int](Get-Content $startTsFile -Raw).Trim()
}
Write-Host "Task start timestamp: $taskStart"

function Get-FileResult {
    param([string]$FilePath)
    if (Test-Path $FilePath) {
        $fi    = Get-Item $FilePath
        $mtime = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
        $content = ""
        try { $content = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue } catch {}
        return @{
            exists     = $true
            size_bytes = [long]$fi.Length
            mtime_unix = $mtime
            is_new     = ($mtime -gt $taskStart)
            content_snippet = if ($content.Length -gt 2000) { $content.Substring(0, 2000) } else { $content }
        }
    }
    return @{ exists = $false; size_bytes = 0; mtime_unix = 0; is_new = $false; content_snippet = "" }
}

# Check the HTML output file
$htmlResult = Get-FileResult "C:\Users\Docker\mumps_analysis.html"

# Also check .htm extension (some versions save as .htm)
if (-not $htmlResult.exists) {
    $htmlResult = Get-FileResult "C:\Users\Docker\mumps_analysis.htm"
}

# Check the CSV summary file
$csvResult = Get-FileResult "C:\Users\Docker\mumps_ve_summary.csv"

# Read full content of HTML for keyword analysis (up to 50KB)
$htmlContent = ""
if ($htmlResult.exists) {
    $htmlPath = "C:\Users\Docker\mumps_analysis.html"
    if (-not (Test-Path $htmlPath)) { $htmlPath = "C:\Users\Docker\mumps_analysis.htm" }
    try {
        $rawContent = [System.IO.File]::ReadAllText($htmlPath)
        if ($rawContent.Length -gt 50000) {
            $htmlContent = $rawContent.Substring(0, 50000)
        } else {
            $htmlContent = $rawContent
        }
    } catch {
        $htmlContent = ""
    }
}

# Read CSV content
$csvContent = ""
if ($csvResult.exists) {
    try {
        $csvContent = Get-Content "C:\Users\Docker\mumps_ve_summary.csv" -Raw -ErrorAction SilentlyContinue
        if ($csvContent.Length -gt 5000) { $csvContent = $csvContent.Substring(0, 5000) }
    } catch {}
}

# Keyword analysis of HTML content
$htmlLower = $htmlContent.ToLower()
$hasFreqKeyword    = $htmlLower.Contains("frequency") -or $htmlLower.Contains("freq")
$hasTablesKeyword  = $htmlLower.Contains("odds ratio") -or $htmlLower.Contains("tables") -or $htmlLower.Contains("2x2")
$hasLogisticKw     = $htmlLower.Contains("logistic") -or $htmlLower.Contains("regression")
$hasOrValues       = $htmlLower -match "\d+\.\d+" -and ($htmlLower.Contains("odds") -or $htmlLower.Contains("ratio") -or $htmlLower.Contains("confidence"))
$hasVaccinationKw  = $htmlLower.Contains("vacc") -or $htmlLower.Contains("immun") -or $htmlLower.Contains("dose") -or $htmlLower.Contains("mmr")
$hasIllnessKw      = $htmlLower.Contains("ill") -or $htmlLower.Contains("case") -or $htmlLower.Contains("disease") -or $htmlLower.Contains("outcome")

$result = [ordered]@{
    task              = "mumps_vaccine_effectiveness_analysis"
    task_start        = $taskStart
    html_output       = @{
        exists           = $htmlResult.exists
        size_bytes       = $htmlResult.size_bytes
        mtime_unix       = $htmlResult.mtime_unix
        is_new           = $htmlResult.is_new
        has_freq_keyword = $hasFreqKeyword
        has_tables_kw    = $hasTablesKeyword
        has_logistic_kw  = $hasLogisticKw
        has_or_values    = $hasOrValues
        has_vaccination_kw = $hasVaccinationKw
        has_illness_kw   = $hasIllnessKw
    }
    csv_output        = @{
        exists     = $csvResult.exists
        size_bytes = $csvResult.size_bytes
        mtime_unix = $csvResult.mtime_unix
        is_new     = $csvResult.is_new
        content    = $csvContent
    }
}

$result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
Write-Host "=== Export Complete: result saved to $resultPath ==="
