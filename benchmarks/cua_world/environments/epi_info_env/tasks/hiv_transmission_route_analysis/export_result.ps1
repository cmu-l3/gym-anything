# Export: hiv_transmission_route_analysis

. "C:\workspace\scripts\task_utils.ps1"

Write-Host "=== Exporting hiv_transmission_route_analysis Result ==="

$resultPath  = "C:\Users\Docker\hiv_transmission_route_analysis_result.json"
$startTsFile = "C:\Users\Docker\task_start_ts_hiv_transmission.txt"

$taskStart = 0
if (Test-Path $startTsFile) {
    $taskStart = [int](Get-Content $startTsFile -Raw).Trim()
}
Write-Host "Task start timestamp: $taskStart"

function Get-FileResult {
    param([string]$FilePath, [bool]$ReadContent = $false, [int]$MaxLen = 2000)
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

# Read HTML content for keyword analysis
$htmlPath = "C:\Users\Docker\hiv_transmission_analysis.html"
if (-not (Test-Path $htmlPath)) { $htmlPath = "C:\Users\Docker\hiv_transmission_analysis.htm" }
$htmlResult = Get-FileResult $htmlPath -ReadContent $true -MaxLen 60000

$csvResult = Get-FileResult "C:\Users\Docker\hiv_transmission_summary.csv" -ReadContent $true -MaxLen 5000

$htmlLower = $htmlResult.content.ToLower()

$hasFreqKw          = $htmlLower.Contains("frequency") -or $htmlLower.Contains("freq")
$hasTransmissionKw  = $htmlLower.Contains("transmiss") -or $htmlLower.Contains("route") -or $htmlLower.Contains("exposure")
$hasDemoKw          = $htmlLower.Contains("sex") -or $htmlLower.Contains("age") -or $htmlLower.Contains("race") -or $htmlLower.Contains("ethnic")
$hasTablesKw        = $htmlLower.Contains("odds ratio") -or $htmlLower.Contains("tables") -or $htmlLower.Contains("chi") -or $htmlLower.Contains("p-value")
$hasSelectEvidence  = $htmlLower.Contains("select") -or $htmlLower.Contains("subset") -or $htmlLower.Contains("male") -or $htmlLower.Contains("female")
$hasMeansKw         = $htmlLower.Contains("mean") -or $htmlLower.Contains("standard deviation") -or $htmlLower.Contains("median")
$hasHivKw           = $htmlLower.Contains("hiv") -or $htmlLower.Contains("aids") -or $htmlLower.Contains("cd4") -or $htmlLower.Contains("case")

$result = [ordered]@{
    task        = "hiv_transmission_route_analysis"
    task_start  = $taskStart
    html_output = @{
        exists              = $htmlResult.exists
        size_bytes          = $htmlResult.size_bytes
        mtime_unix          = $htmlResult.mtime_unix
        is_new              = $htmlResult.is_new
        has_freq_kw         = $hasFreqKw
        has_transmission_kw = $hasTransmissionKw
        has_demo_kw         = $hasDemoKw
        has_tables_kw       = $hasTablesKw
        has_select_evidence = $hasSelectEvidence
        has_means_kw        = $hasMeansKw
        has_hiv_kw          = $hasHivKw
    }
    csv_output  = @{
        exists     = $csvResult.exists
        size_bytes = $csvResult.size_bytes
        mtime_unix = $csvResult.mtime_unix
        is_new     = $csvResult.is_new
    }
}

$result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
Write-Host "=== Export Complete ==="
