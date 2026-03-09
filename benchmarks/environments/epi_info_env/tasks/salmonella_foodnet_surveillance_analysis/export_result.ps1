# Export: salmonella_foodnet_surveillance_analysis

. "C:\workspace\scripts\task_utils.ps1"

Write-Host "=== Exporting salmonella_foodnet_surveillance_analysis Result ==="

$resultPath  = "C:\Users\Docker\salmonella_foodnet_surveillance_analysis_result.json"
$startTsFile = "C:\Users\Docker\task_start_ts_salmonella.txt"

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

$htmlPath = "C:\Users\Docker\salmonella_surveillance_report.html"
if (-not (Test-Path $htmlPath)) { $htmlPath = "C:\Users\Docker\salmonella_surveillance_report.htm" }
$htmlResult = Get-FileResult $htmlPath -ReadContent $true -MaxLen 80000
$csvResult  = Get-FileResult "C:\Users\Docker\salmonella_serotype_summary.csv" -ReadContent $true -MaxLen 5000

$htmlLower = $htmlResult.content.ToLower()

$hasFreqKw       = $htmlLower.Contains("frequency") -or $htmlLower.Contains("freq")
$hasSerotypeKw   = $htmlLower.Contains("enteritidis") -or $htmlLower.Contains("typhimurium") -or $htmlLower.Contains("newport") -or $htmlLower.Contains("serotype")
$hasSiteKw       = $htmlLower.Contains(" ca ") -or $htmlLower.Contains(" ga ") -or $htmlLower.Contains(" mn ") -or $htmlLower.Contains("site") -or $htmlLower.Contains("state")
$hasMeansKw      = $htmlLower.Contains("mean") -or $htmlLower.Contains("incidence") -or $htmlLower.Contains("rate")
$hasTablesKw     = $htmlLower.Contains("tables") -or $htmlLower.Contains("chi") -or $htmlLower.Contains("p-value") -or $htmlLower.Contains("odds")
$hasSelectKw     = $htmlLower.Contains("select") -or $htmlLower.Contains("year") -or $htmlLower.Contains("2017") -or $htmlLower.Contains("2018") -or $htmlLower.Contains("2019")
$hasSalmonellaKw = $htmlLower.Contains("salmonella") -or $htmlLower.Contains("foodnet") -or $htmlLower.Contains("surveillance")

$result = [ordered]@{
    task        = "salmonella_foodnet_surveillance_analysis"
    task_start  = $taskStart
    html_output = @{
        exists            = $htmlResult.exists
        size_bytes        = $htmlResult.size_bytes
        mtime_unix        = $htmlResult.mtime_unix
        is_new            = $htmlResult.is_new
        has_freq_kw       = $hasFreqKw
        has_serotype_kw   = $hasSerotypeKw
        has_site_kw       = $hasSiteKw
        has_means_kw      = $hasMeansKw
        has_tables_kw     = $hasTablesKw
        has_select_kw     = $hasSelectKw
        has_salmonella_kw = $hasSalmonellaKw
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
