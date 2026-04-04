# Setup script for compare_surgical_cases task
# Launches Vital Recorder with an empty workspace (no file pre-loaded).
# Both 0001.vital and 0002.vital are placed in VitalRecorderData.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_compare_surgical_cases.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { Write-Host "WARNING: Start-Transcript failed" }

try {
    Write-Host "=== Setting up compare_surgical_cases task ==="

    # Load shared helpers
    . "C:\workspace\scripts\task_utils.ps1"

    # Kill any running Vital Recorder instances
    Get-Process -Name "Vital" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Ensure data directory and both files exist
    $dataDir = "C:\Users\Docker\Desktop\VitalRecorderData"
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

    $dataFile1 = "$dataDir\0001.vital"
    $dataFile2 = "$dataDir\0002.vital"

    if (-not (Test-Path $dataFile1)) {
        Copy-Item "C:\workspace\data\0001.vital" -Destination $dataFile1 -Force
    }
    Write-Host "Data file 1 ready at: $dataFile1"

    if (-not (Test-Path $dataFile2)) {
        Copy-Item "C:\workspace\data\0002.vital" -Destination $dataFile2 -Force
    }
    Write-Host "Data file 2 ready at: $dataFile2"

    # Remove any previous output files
    $outputFiles = @(
        "C:\Users\Docker\Desktop\case_0001_data.csv",
        "C:\Users\Docker\Desktop\case_0002_data.csv",
        "C:\Users\Docker\Desktop\case_comparison.txt"
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
        data_file_1     = $dataFile1
        data_file_2     = $dataFile2
        data_file_1_exists = (Test-Path $dataFile1)
        data_file_2_exists = (Test-Path $dataFile2)
        desktop_files   = @(Get-ChildItem "C:\Users\Docker\Desktop" -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    }
    $baseline | ConvertTo-Json -Depth 4 | Out-File -FilePath "C:\Users\Docker\task_baseline_compare.json" -Encoding UTF8 -Force
    Write-Host "Baseline state recorded to task_baseline_compare.json"

    # Launch Vital Recorder with empty workspace (no file argument)
    $vrExe = Find-VitalRecorderExe
    Write-Host "Vital Recorder executable: $vrExe"
    Launch-VitalRecorderInteractive -VitalRecorderExe $vrExe -WaitSeconds 20

    # Dismiss any dialogs
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Run-InteractiveScript -ScriptPath $dismissScript -TaskName "DismissDialogs_Compare" -WaitSeconds 12
    }

    # Verify Vital Recorder is running
    if (Test-VitalRecorderRunning) {
        Write-Host "Vital Recorder is running with empty workspace"
    } else {
        Write-Host "WARNING: Vital Recorder process not found"
    }

    Write-Host "=== compare_surgical_cases task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
