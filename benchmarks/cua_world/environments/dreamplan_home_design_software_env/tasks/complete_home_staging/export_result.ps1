# Export script for complete_home_staging task.
# Checks for 3 required room-view image files and writes a result JSON.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_home_staging_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting complete_home_staging result ==="

    $startTsFile = "C:\Users\Docker\task_start_ts_home_staging.txt"
    $resultPath  = "C:\Users\Docker\complete_home_staging_result.json"

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
    $rliving  = Get-FileResult "C:\Users\Docker\Desktop\staged_living_room.jpg"
    $rdining  = Get-FileResult "C:\Users\Docker\Desktop\staged_dining_room.jpg"
    $rbedroom = Get-FileResult "C:\Users\Docker\Desktop\staged_bedroom.jpg"

    Write-Host "staged_living_room.jpg : exists=$($rliving.exists), is_new=$($rliving.is_new), size=$($rliving.size_bytes)"
    Write-Host "staged_dining_room.jpg : exists=$($rdining.exists), is_new=$($rdining.is_new), size=$($rdining.size_bytes)"
    Write-Host "staged_bedroom.jpg     : exists=$($rbedroom.exists), is_new=$($rbedroom.is_new), size=$($rbedroom.size_bytes)"

    # Build result JSON
    $result = [ordered]@{
        task        = "complete_home_staging"
        task_start  = $taskStart
        staged_living_room_jpg = $rliving
        staged_dining_room_jpg = $rdining
        staged_bedroom_jpg     = $rbedroom
    }

    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written to: $resultPath"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
