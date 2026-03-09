# Setup script for configure_track_display task
# Opens Vital Recorder with 0003.vital loaded

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_configure_track_display.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { Write-Host "WARNING: Start-Transcript failed" }

try {
    Write-Host "=== Setting up configure_track_display task ==="

    # Load shared helpers
    . "C:\workspace\scripts\task_utils.ps1"

    # Kill any running Vital Recorder instances
    Get-Process -Name "Vital" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Ensure data file exists
    $dataDir = "C:\Users\Docker\Desktop\VitalRecorderData"
    $dataFile = "$dataDir\0003.vital"
    if (-not (Test-Path $dataFile)) {
        New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
        Copy-Item "C:\workspace\data\0003.vital" -Destination $dataFile -Force
    }
    Write-Host "Data file ready at: $dataFile"

    # Launch Vital Recorder with the data file
    $vrExe = Find-VitalRecorderExe
    Write-Host "Vital Recorder executable: $vrExe"
    Launch-VitalRecorderInteractive -VitalRecorderExe $vrExe -FileToOpen $dataFile -WaitSeconds 20

    # Dismiss any dialogs
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Run-InteractiveScript -ScriptPath $dismissScript -TaskName "DismissDialogs_TrackDisplay" -WaitSeconds 12
    }

    # Verify Vital Recorder is running
    if (Test-VitalRecorderRunning) {
        Write-Host "Vital Recorder is running with 0003.vital loaded"
    } else {
        Write-Host "WARNING: Vital Recorder process not found"
    }

    Write-Host "=== configure_track_display task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
