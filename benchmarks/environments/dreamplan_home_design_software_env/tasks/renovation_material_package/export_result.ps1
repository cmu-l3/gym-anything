# Export script for renovation_material_package task.
# Checks for the 3 required output files and writes a result JSON.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_renovation_material_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting renovation_material_package result ==="

    $startTsFile = "C:\Users\Docker\task_start_ts_renovation_material.txt"
    $resultPath  = "C:\Users\Docker\renovation_material_package_result.json"

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
    $r3d       = Get-FileResult "C:\Users\Docker\Desktop\renovation_3d_view.jpg"
    $rblue     = Get-FileResult "C:\Users\Docker\Desktop\renovation_floor_plan.jpg"
    $rproject  = Get-FileResult "C:\Users\Docker\Documents\renovation_proposal.dpn"

    Write-Host "renovation_3d_view.jpg   : exists=$($r3d.exists), is_new=$($r3d.is_new), size=$($r3d.size_bytes)"
    Write-Host "renovation_floor_plan.jpg: exists=$($rblue.exists), is_new=$($rblue.is_new), size=$($rblue.size_bytes)"
    Write-Host "renovation_proposal.dpn  : exists=$($rproject.exists), is_new=$($rproject.is_new)"

    # Build result JSON using PowerShell hashtable → ConvertTo-Json
    $result = [ordered]@{
        task        = "renovation_material_package"
        task_start  = $taskStart
        renovation_3d_view_jpg    = $r3d
        renovation_floor_plan_jpg = $rblue
        renovation_proposal_dpn   = $rproject
    }

    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written to: $resultPath"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
