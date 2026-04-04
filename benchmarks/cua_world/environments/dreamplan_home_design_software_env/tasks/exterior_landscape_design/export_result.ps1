# Export script for exterior_landscape_design task.
# Checks for 3 required output files (site plan, 3D exterior, project)
# and writes a result JSON.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_landscape_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting exterior_landscape_design result ==="

    $startTsFile = "C:\Users\Docker\task_start_ts_landscape.txt"
    $resultPath  = "C:\Users\Docker\exterior_landscape_design_result.json"

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
    $rsiteplan = Get-FileResult "C:\Users\Docker\Desktop\landscape_site_plan.jpg"
    $r3d       = Get-FileResult "C:\Users\Docker\Desktop\landscape_3d_view.jpg"
    $rproject  = Get-FileResult "C:\Users\Docker\Documents\landscape_design.dpn"

    Write-Host "landscape_site_plan.jpg: exists=$($rsiteplan.exists), is_new=$($rsiteplan.is_new), size=$($rsiteplan.size_bytes)"
    Write-Host "landscape_3d_view.jpg  : exists=$($r3d.exists), is_new=$($r3d.is_new), size=$($r3d.size_bytes)"
    Write-Host "landscape_design.dpn   : exists=$($rproject.exists), is_new=$($rproject.is_new)"

    # Build result JSON
    $result = [ordered]@{
        task        = "exterior_landscape_design"
        task_start  = $taskStart
        landscape_site_plan_jpg = $rsiteplan
        landscape_3d_view_jpg   = $r3d
        landscape_design_dpn    = $rproject
    }

    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written to: $resultPath"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
