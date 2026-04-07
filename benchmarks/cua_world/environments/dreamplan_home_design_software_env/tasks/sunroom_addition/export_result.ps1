# Export script for sunroom_addition task.
# Checks for 4 required output files (3 images + 1 project)
# and writes a result JSON.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_sunroom_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting sunroom_addition result ==="

    $startTsFile = "C:\Users\Docker\task_start_ts_sunroom.txt"
    $resultPath  = "C:\Users\Docker\sunroom_addition_result.json"

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
    $rFloorplan = Get-FileResult "C:\Users\Docker\Desktop\sunroom_floorplan.jpg"
    $rExterior  = Get-FileResult "C:\Users\Docker\Desktop\sunroom_exterior.jpg"
    $rInterior  = Get-FileResult "C:\Users\Docker\Desktop\sunroom_interior.jpg"
    $rProject   = Get-FileResult "C:\Users\Docker\Documents\sunroom_design.dpn"

    Write-Host "sunroom_floorplan.jpg : exists=$($rFloorplan.exists), is_new=$($rFloorplan.is_new), size=$($rFloorplan.size_bytes)"
    Write-Host "sunroom_exterior.jpg  : exists=$($rExterior.exists), is_new=$($rExterior.is_new), size=$($rExterior.size_bytes)"
    Write-Host "sunroom_interior.jpg  : exists=$($rInterior.exists), is_new=$($rInterior.is_new), size=$($rInterior.size_bytes)"
    Write-Host "sunroom_design.dpn    : exists=$($rProject.exists), is_new=$($rProject.is_new)"

    # Check if DreamPlan is still running
    $appRunning = (Get-Process -Name "dreamplan" -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0

    # Build result JSON
    $result = [ordered]@{
        task                   = "sunroom_addition"
        task_start             = $taskStart
        sunroom_floorplan_jpg  = $rFloorplan
        sunroom_exterior_jpg   = $rExterior
        sunroom_interior_jpg   = $rInterior
        sunroom_design_dpn     = $rProject
        app_was_running        = $appRunning
    }

    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written to: $resultPath"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
