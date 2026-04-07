# Export result script for customer_value_segmentation task.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_post_task_customer_value_segmentation.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting customer_value_segmentation result ==="

    $resultPath  = "C:\Users\Docker\customer_value_segmentation_result.json"
    $startTsFile = "C:\Users\Docker\task_start_ts_cust_val_seg.txt"

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
        "C:\Users\Docker\Documents\customer_value_segmentation.dva",
        "C:\Users\Docker\Desktop\customer_value_segmentation.dva",
        "C:\Users\Docker\customer_value_segmentation.dva"
    )

    $dvaResult = [ordered]@{ exists=$false; size_bytes=0; mtime_unix=0; is_new=$false; path="" }
    foreach ($p in $searchPaths) {
        $r = Get-FileResult $p
        if ($r.exists) { $dvaResult = $r; break }
    }

    # Scan Documents for customer-related .dva
    if (-not $dvaResult.exists) {
        $docsDir = "C:\Users\Docker\Documents"
        if (Test-Path $docsDir) {
            $found = Get-ChildItem $docsDir -Filter "*.dva" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "customer|segment|value|ltv" } |
                Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
            if ($found) {
                $mtime = [int][DateTimeOffset]::new($found.LastWriteTimeUtc).ToUnixTimeSeconds()
                $dvaResult = [ordered]@{ exists=$true; size_bytes=[long]$found.Length; mtime_unix=$mtime; is_new=($mtime -gt $taskStart); path=$found.FullName }
            }
        }
    }

    $result = [ordered]@{
        task       = "customer_value_segmentation"
        task_start = $taskStart
        dva_file   = $dvaResult
    }

    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written: dva_exists=$($dvaResult.exists), is_new=$($dvaResult.is_new)"
    Write-Host "=== Export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
