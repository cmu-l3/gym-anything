# Export script for construction_document_set task.
# Checks for 5 required output files (4 images + 1 project file)
# and writes a result JSON.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_construction_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting construction_document_set result ==="

    $startTsFile = "C:\Users\Docker\task_start_ts_construction.txt"
    $resultPath  = "C:\Users\Docker\construction_document_set_result.json"

    # Read task start timestamp
    $taskStart = 0
    if (Test-Path $startTsFile) {
        try { $taskStart = [int](Get-Content $startTsFile -Raw).Trim() } catch { }
    }
    Write-Host "Task start timestamp: $taskStart"

    # Helper: get file info as hashtable
    function Get-FileResult {
        param([string]$FilePath)
        if (Test-Path $FilePath) {
            $fi    = Get-Item $FilePath
            $mtime = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
            return @{
                exists     = $true
                size_bytes = [long]$fi.Length
                mtime_unix = $mtime
                is_new     = ($mtime -gt $taskStart)
            }
        }
        return @{ exists = $false; size_bytes = 0; mtime_unix = 0; is_new = $false }
    }

    # Check each required output file
    $refront  = Get-FileResult "C:\Users\Docker\Desktop\elevation_front.jpg"
    $reside   = Get-FileResult "C:\Users\Docker\Desktop\elevation_side.jpg"
    $refloor  = Get-FileResult "C:\Users\Docker\Desktop\construction_floor_plan.jpg"
    $reoverview = Get-FileResult "C:\Users\Docker\Desktop\construction_overview.jpg"
    $rproject = Get-FileResult "C:\Users\Docker\Documents\construction_docs.dpn"

    Write-Host "elevation_front.jpg        : exists=$($refront.exists), is_new=$($refront.is_new), size=$($refront.size_bytes)"
    Write-Host "elevation_side.jpg         : exists=$($reside.exists), is_new=$($reside.is_new), size=$($reside.size_bytes)"
    Write-Host "construction_floor_plan.jpg: exists=$($refloor.exists), is_new=$($refloor.is_new), size=$($refloor.size_bytes)"
    Write-Host "construction_overview.jpg  : exists=$($reoverview.exists), is_new=$($reoverview.is_new), size=$($reoverview.size_bytes)"
    Write-Host "construction_docs.dpn      : exists=$($rproject.exists), is_new=$($rproject.is_new)"

    # Build result JSON
    $result = [ordered]@{
        task        = "construction_document_set"
        task_start  = $taskStart
        elevation_front_jpg         = $refront
        elevation_side_jpg          = $reside
        construction_floor_plan_jpg = $refloor
        construction_overview_jpg   = $reoverview
        construction_docs_dpn       = $rproject
    }

    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written to: $resultPath"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
