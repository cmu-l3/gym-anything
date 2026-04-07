# Export result script for pl_attribution_dashboard task.
# Records workbook file state for verifier.py.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_post_task_pl_attribution_dashboard.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch { }

try {
    Write-Host "=== Exporting pl_attribution_dashboard result ==="

    $resultPath  = "C:\Users\Docker\pl_attribution_dashboard_result.json"
    $startTsFile = "C:\Users\Docker\task_start_ts_pl_attribution.txt"

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
            return [ordered]@{
                exists     = $true
                size_bytes = [long]$fi.Length
                mtime_unix = $mtime
                is_new     = ($mtime -gt $taskStart)
                path       = $FilePath
            }
        }
        return [ordered]@{ exists=$false; size_bytes=0; mtime_unix=0; is_new=$false; path=$FilePath }
    }

    # Search for the workbook file in common save locations
    $searchPaths = @(
        "C:\Users\Docker\Documents\pl_attribution.dva",
        "C:\Users\Docker\Desktop\pl_attribution.dva",
        "C:\Users\Docker\pl_attribution.dva"
    )

    $dvaResult = [ordered]@{ exists=$false; size_bytes=0; mtime_unix=0; is_new=$false; path="" }
    foreach ($p in $searchPaths) {
        $r = Get-FileResult $p
        if ($r.exists) {
            $dvaResult = $r
            break
        }
    }

    # Also scan Documents folder for any .dva file saved with a variant name
    $docsDir = "C:\Users\Docker\Documents"
    $scanResult = [ordered]@{ exists=$false; size_bytes=0; mtime_unix=0; is_new=$false; path="" }
    if (Test-Path $docsDir) {
        $found = Get-ChildItem $docsDir -Filter "*.dva" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "pl_attribution|attribution|profitability" } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($found) {
            $mtime = [int][DateTimeOffset]::new($found.LastWriteTimeUtc).ToUnixTimeSeconds()
            $scanResult = [ordered]@{
                exists     = $true
                size_bytes = [long]$found.Length
                mtime_unix = $mtime
                is_new     = ($mtime -gt $taskStart)
                path       = $found.FullName
            }
        }
    }

    # Use specific path result if found, else fall back to scan result
    $finalDva = if ($dvaResult.exists) { $dvaResult } else { $scanResult }

    $result = [ordered]@{
        task            = "pl_attribution_dashboard"
        task_start      = $taskStart
        dva_file        = $finalDva
    }

    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written to: $resultPath"
    Write-Host "DVA file found: $($finalDva.exists), path: $($finalDva.path), is_new: $($finalDva.is_new)"

    Write-Host "=== Export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
