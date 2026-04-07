# Export result script for unit_economics_analysis task.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_post_task_unit_economics_analysis.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting unit_economics_analysis result ==="

    $resultPath  = "C:\Users\Docker\unit_economics_analysis_result.json"
    $startTsFile = "C:\Users\Docker\task_start_ts_unit_econ.txt"

    $taskStart = 0
    if (Test-Path $startTsFile) {
        $taskStart = [int](Get-Content $startTsFile -Raw).Trim()
    }

    function Get-FileResult {
        param([string]$FilePath)
        if (Test-Path $FilePath) {
            $fi    = Get-Item $FilePath
            $mtime = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
            return [ordered]@{ exists=$true; size_bytes=[long]$fi.Length; mtime_unix=$mtime; is_new=($mtime -gt $taskStart); path=$FilePath }
        }
        return [ordered]@{ exists=$false; size_bytes=0; mtime_unix=0; is_new=$false; path=$FilePath }
    }

    $searchPaths = @(
        "C:\Users\Docker\Documents\unit_economics.dva",
        "C:\Users\Docker\Desktop\unit_economics.dva",
        "C:\Users\Docker\unit_economics.dva"
    )

    $dvaResult = [ordered]@{ exists=$false; size_bytes=0; mtime_unix=0; is_new=$false; path="" }
    foreach ($p in $searchPaths) {
        $r = Get-FileResult $p
        if ($r.exists) { $dvaResult = $r; break }
    }

    # Scan Documents for any unit-economics-related .dva
    if (-not $dvaResult.exists) {
        $docsDir = "C:\Users\Docker\Documents"
        if (Test-Path $docsDir) {
            $found = Get-ChildItem $docsDir -Filter "*.dva" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "unit_economics|unit_econ|profitability_tier" } |
                Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
            if ($found) {
                $mtime = [int][DateTimeOffset]::new($found.LastWriteTimeUtc).ToUnixTimeSeconds()
                $dvaResult = [ordered]@{ exists=$true; size_bytes=[long]$found.Length; mtime_unix=$mtime; is_new=($mtime -gt $taskStart); path=$found.FullName }
            }
        }
    }

    $result = [ordered]@{
        task       = "unit_economics_analysis"
        task_start = $taskStart
        dva_file   = $dvaResult
    }

    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written: dva_exists=$($dvaResult.exists), is_new=$($dvaResult.is_new)"
    Write-Host "=== Export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
