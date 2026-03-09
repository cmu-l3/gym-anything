# Setup script for configure_multicase_review task
# Opens Vital Recorder with 0003.vital already loaded in Track mode

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_configure_multicase_review.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { Write-Host "WARNING: Start-Transcript failed" }

try {
    Write-Host "=== Setting up configure_multicase_review task ==="

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

    # Remove any previous output files
    $outputFiles = @(
        "C:\Users\Docker\Desktop\case_0003_review.csv",
        "C:\Users\Docker\Desktop\monitor_view_0003.png"
    )
    foreach ($f in $outputFiles) {
        if (Test-Path $f) {
            Remove-Item $f -Force -ErrorAction SilentlyContinue
            Write-Host "Removed previous output: $f"
        }
    }

    # Record baseline state
    $baseline = @{
        timestamp       = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        data_file       = $dataFile
        data_file_exists = (Test-Path $dataFile)
        desktop_files   = @(Get-ChildItem "C:\Users\Docker\Desktop" -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    }
    $baseline | ConvertTo-Json -Depth 4 | Out-File -FilePath "C:\Users\Docker\task_baseline_multicase.json" -Encoding UTF8 -Force
    Write-Host "Baseline state recorded to task_baseline_multicase.json"

    # Launch Vital Recorder with the data file (opens in Track mode by default)
    $vrExe = Find-VitalRecorderExe
    Write-Host "Vital Recorder executable: $vrExe"
    Launch-VitalRecorderInteractive -VitalRecorderExe $vrExe -FileToOpen $dataFile -WaitSeconds 20

    # Dismiss any dialogs
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Run-InteractiveScript -ScriptPath $dismissScript -TaskName "DismissDialogs_MultiCase" -WaitSeconds 12
    }

    # Verify Vital Recorder is running
    if (Test-VitalRecorderRunning) {
        Write-Host "Vital Recorder is running with 0003.vital loaded"
    } else {
        Write-Host "WARNING: Vital Recorder process not found"
    }

    Write-Host "=== configure_multicase_review task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
