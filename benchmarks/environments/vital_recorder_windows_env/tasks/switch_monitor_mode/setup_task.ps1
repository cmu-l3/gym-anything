# Setup script for switch_monitor_mode task
# Opens Vital Recorder with 0001.vital loaded in Track mode

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_switch_monitor_mode.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { Write-Host "WARNING: Start-Transcript failed" }

try {
    Write-Host "=== Setting up switch_monitor_mode task ==="

    # Load shared helpers
    . "C:\workspace\scripts\task_utils.ps1"

    # Kill any running Vital Recorder instances
    Get-Process -Name "Vital" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Ensure data file exists
    $dataDir = "C:\Users\Docker\Desktop\VitalRecorderData"
    $dataFile = "$dataDir\0001.vital"
    if (-not (Test-Path $dataFile)) {
        New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
        Copy-Item "C:\workspace\data\0001.vital" -Destination $dataFile -Force
    }
    Write-Host "Data file ready at: $dataFile"

    # Launch Vital Recorder with the data file (opens in Track mode by default)
    $vrExe = Find-VitalRecorderExe
    Write-Host "Vital Recorder executable: $vrExe"
    Launch-VitalRecorderInteractive -VitalRecorderExe $vrExe -FileToOpen $dataFile -WaitSeconds 20

    # Dismiss any dialogs
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Run-InteractiveScript -ScriptPath $dismissScript -TaskName "DismissDialogs_Monitor" -WaitSeconds 12
    }

    # Verify Vital Recorder is running
    if (Test-VitalRecorderRunning) {
        Write-Host "Vital Recorder is running in Track mode with 0001.vital loaded"
    } else {
        Write-Host "WARNING: Vital Recorder process not found"
    }

    Write-Host "=== switch_monitor_mode task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
