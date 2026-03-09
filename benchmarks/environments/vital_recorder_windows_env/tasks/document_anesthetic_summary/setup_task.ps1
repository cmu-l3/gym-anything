# Setup script for document_anesthetic_summary task
# Opens Vital Recorder with 0002.vital already loaded

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_document_anesthetic_summary.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { Write-Host "WARNING: Start-Transcript failed" }

try {
    Write-Host "=== Setting up document_anesthetic_summary task ==="

    # Load shared helpers
    . "C:\workspace\scripts\task_utils.ps1"

    # Kill any running Vital Recorder instances
    Get-Process -Name "Vital" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Ensure data directory and file exist
    $dataDir = "C:\Users\Docker\Desktop\VitalRecorderData"
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

    $dataFile = "$dataDir\0002.vital"
    if (-not (Test-Path $dataFile)) {
        Copy-Item "C:\workspace\data\0002.vital" -Destination $dataFile -Force
    }
    Write-Host "Data file ready at: $dataFile"

    # Remove any previous output files
    $outputFiles = @(
        "C:\Users\Docker\Desktop\case_0002_vitals.csv",
        "C:\Users\Docker\Desktop\anesthetic_summary_0002.txt"
    )
    foreach ($f in $outputFiles) {
        if (Test-Path $f) {
            Remove-Item $f -Force -ErrorAction SilentlyContinue
            Write-Host "Removed previous output: $f"
        }
    }

    # Record baseline state
    $baseline = @{
        timestamp        = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        data_file        = $dataFile
        data_file_exists = (Test-Path $dataFile)
        desktop_files    = @(Get-ChildItem "C:\Users\Docker\Desktop" -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    }
    $baseline | ConvertTo-Json -Depth 4 | Out-File -FilePath "C:\Users\Docker\task_baseline_summary.json" -Encoding UTF8 -Force
    Write-Host "Baseline state recorded to task_baseline_summary.json"

    # Launch Vital Recorder with the data file
    $vrExe = Find-VitalRecorderExe
    Write-Host "Vital Recorder executable: $vrExe"
    Launch-VitalRecorderInteractive -VitalRecorderExe $vrExe -FileToOpen $dataFile -WaitSeconds 20

    # Dismiss any dialogs
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Run-InteractiveScript -ScriptPath $dismissScript -TaskName "DismissDialogs_Summary" -WaitSeconds 12
    }

    # Verify Vital Recorder is running
    if (Test-VitalRecorderRunning) {
        Write-Host "Vital Recorder is running with 0002.vital loaded"
    } else {
        Write-Host "WARNING: Vital Recorder process not found"
    }

    Write-Host "=== document_anesthetic_summary task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
