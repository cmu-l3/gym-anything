# Export script for second_floor_addition task.
# Checks for 4 required output files (2 floor plans, 1 exterior 3D, 1 project)
# and writes a result JSON.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_second_floor_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting second_floor_addition result ==="

    $startTsFile = "C:\Users\Docker\task_start_ts_second_floor.txt"
    $resultPath  = "C:\Users\Docker\second_floor_addition_result.json"

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
    $rground   = Get-FileResult "C:\Users\Docker\Desktop\ground_floor_plan.jpg"
    $rsecond   = Get-FileResult "C:\Users\Docker\Desktop\second_floor_plan.jpg"
    $rexterior = Get-FileResult "C:\Users\Docker\Desktop\two_story_exterior.jpg"
    $rproject  = Get-FileResult "C:\Users\Docker\Documents\two_story_design.dpn"

    Write-Host "ground_floor_plan.jpg  : exists=$($rground.exists), is_new=$($rground.is_new), size=$($rground.size_bytes)"
    Write-Host "second_floor_plan.jpg  : exists=$($rsecond.exists), is_new=$($rsecond.is_new), size=$($rsecond.size_bytes)"
    Write-Host "two_story_exterior.jpg : exists=$($rexterior.exists), is_new=$($rexterior.is_new), size=$($rexterior.size_bytes)"
    Write-Host "two_story_design.dpn   : exists=$($rproject.exists), is_new=$($rproject.is_new)"

    # Build result JSON
    $result = [ordered]@{
        task        = "second_floor_addition"
        task_start  = $taskStart
        ground_floor_plan_jpg  = $rground
        second_floor_plan_jpg  = $rsecond
        two_story_exterior_jpg = $rexterior
        two_story_design_dpn   = $rproject
    }

    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written to: $resultPath"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
