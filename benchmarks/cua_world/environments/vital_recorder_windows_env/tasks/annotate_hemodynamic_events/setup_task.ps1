# Setup script for annotate_hemodynamic_events task
# Opens Vital Recorder with 0001.vital loaded and records baseline event count

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_annotate_hemodynamic_events.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { Write-Host "WARNING: Start-Transcript failed" }

try {
    Write-Host "=== Setting up annotate_hemodynamic_events task ==="

    # Load shared helpers
    . "C:\workspace\scripts\task_utils.ps1"

    # Kill any running Vital Recorder instances
    Get-Process -Name "Vital" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Ensure data file exists in VitalRecorderData
    $dataDir = "C:\Users\Docker\Desktop\VitalRecorderData"
    $dataFile = "$dataDir\0001.vital"
    if (-not (Test-Path $dataFile)) {
        New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
        Copy-Item "C:\workspace\data\0001.vital" -Destination $dataFile -Force
    }
    Write-Host "Data file ready at: $dataFile"

    # Remove any previous annotated CSV export
    $csvPath = "C:\Users\Docker\Desktop\annotated_0001.csv"
    if (Test-Path $csvPath) {
        Remove-Item $csvPath -Force -ErrorAction SilentlyContinue
        Write-Host "Removed previous CSV export at: $csvPath"
    }

    # Record baseline state (initial event count and timestamp)
    $baseline = @{
        initial_event_count = 4
        initial_events = @("Case started", "Surgery started", "Surgery finished", "Case finished")
        task_start_time = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        data_file = $dataFile
        csv_path = $csvPath
    }
    $baselineJson = $baseline | ConvertTo-Json -Depth 4
    $baselineJson | Out-File -FilePath "C:\Users\Docker\task_baseline_annotate.json" -Encoding UTF8 -Force
    Write-Host "Baseline recorded: 4 initial events"

    # Launch Vital Recorder with the data file
    $vrExe = Find-VitalRecorderExe
    Write-Host "Vital Recorder executable: $vrExe"
    Launch-VitalRecorderInteractive -VitalRecorderExe $vrExe -FileToOpen $dataFile -WaitSeconds 20

    # Dismiss any dialogs
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Run-InteractiveScript -ScriptPath $dismissScript -TaskName "DismissDialogs_Annotate" -WaitSeconds 12
    }

    # Verify Vital Recorder is running
    if (Test-VitalRecorderRunning) {
        Write-Host "Vital Recorder is running with 0001.vital loaded"
    } else {
        Write-Host "WARNING: Vital Recorder process not found"
    }

    Write-Host "=== annotate_hemodynamic_events task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
