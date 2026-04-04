# Setup script for export_intraoperative_segment task
# Opens Vital Recorder with 0001.vital loaded and records baseline timestamp

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_export_intraop.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { Write-Host "WARNING: Start-Transcript failed" }

try {
    Write-Host "=== Setting up export_intraoperative_segment task ==="

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

    # Remove any previous export file
    $exportPath = "C:\Users\Docker\Desktop\intraop_0001.csv"
    if (Test-Path $exportPath) {
        Remove-Item $exportPath -Force -ErrorAction SilentlyContinue
    }

    # Remove any previous result files
    $resultPath = "C:\Users\Docker\Desktop\task_result_intraop.json"
    if (Test-Path $resultPath) {
        Remove-Item $resultPath -Force -ErrorAction SilentlyContinue
    }

    # Record baseline timestamp for verifier freshness check
    $baselinePath = "C:\Users\Docker\task_baseline_intraop.json"
    $nowUnix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $baselineJson = @{
        task_start_unix = $nowUnix
        task_start_iso  = (Get-Date -Format "o")
        case_file       = "0001.vital"
        export_path     = $exportPath
    } | ConvertTo-Json -Depth 3
    $baselineJson | Out-File -FilePath $baselinePath -Encoding utf8 -Force
    Write-Host "Baseline timestamp recorded: $nowUnix"

    # Launch Vital Recorder with the data file
    $vrExe = Find-VitalRecorderExe
    Write-Host "Vital Recorder executable: $vrExe"
    Launch-VitalRecorderInteractive -VitalRecorderExe $vrExe -FileToOpen $dataFile -WaitSeconds 20

    # Dismiss any dialogs
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Run-InteractiveScript -ScriptPath $dismissScript -TaskName "DismissDialogs_IntraopExport" -WaitSeconds 12
    }

    # Verify Vital Recorder is running
    if (Test-VitalRecorderRunning) {
        Write-Host "Vital Recorder is running with 0001.vital loaded"
    } else {
        Write-Host "WARNING: Vital Recorder process not found"
    }

    Write-Host "=== export_intraoperative_segment task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
