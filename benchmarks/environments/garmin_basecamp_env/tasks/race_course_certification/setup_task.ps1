######################################################################
# setup_task.ps1  -  pre_task hook for race_course_certification
# Start state: BaseCamp open with fells_loop terrain data loaded
######################################################################
$ErrorActionPreference = "Continue"
Start-Transcript -Path "C:\GarminTools\task_race_course.log" -Append | Out-Null
Write-Host "=== Setting up race_course_certification task ==="

. "C:\workspace\scripts\task_utils.ps1"

Close-Browsers
Close-BaseCamp

# Restore BaseCamp data with fells_loop terrain reference data
$restored = Restore-BaseCampData
if (-not $restored) {
    Write-Host "WARNING: Could not restore BaseCamp data"
}

# Record task start timestamp
$taskStart = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$taskStart | Set-Content "C:\GarminTools\race_course_start_ts.txt" -Encoding ASCII
Write-Host "Task start timestamp: $taskStart"

# Remove any leftover export from previous run
$exportPath = "C:\Users\Docker\Desktop\Fells25K_Official_Course_2024.gpx"
if (Test-Path $exportPath) { Remove-Item $exportPath -Force }

# Launch BaseCamp (Task Launcher dismissed automatically)
$bcOk = Launch-BaseCampInteractive -WaitSeconds 80

Close-Browsers

Write-Host "=== race_course_certification task setup complete ==="
Stop-Transcript | Out-Null
