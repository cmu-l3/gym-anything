# Setup script for cross_case_event_timeline_database task
# Launches Vital Recorder with empty workspace.
# Agent must open all three cases, read event markers, and build a cross-case database.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_event_timeline.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { Write-Host "WARNING: Start-Transcript failed" }

try {
    Write-Host "=== Setting up cross_case_event_timeline_database task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    Get-Process -Name "Vital" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $dataDir = "C:\Users\Docker\Desktop\VitalRecorderData"
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

    foreach ($caseNum in @("0001", "0002", "0003")) {
        $destFile = "$dataDir\$caseNum.vital"
        $srcFile  = "C:\workspace\data\$caseNum.vital"
        if (-not (Test-Path $destFile)) {
            if (Test-Path $srcFile) {
                Copy-Item $srcFile -Destination $destFile -Force
                Write-Host "Copied $caseNum.vital"
            } else {
                Write-Host "WARNING: Source not found: $srcFile"
            }
        }
    }

    # Remove previous output files
    $outputFiles = @(
        "C:\Users\Docker\Desktop\case_0001_events.csv",
        "C:\Users\Docker\Desktop\case_0002_events.csv",
        "C:\Users\Docker\Desktop\case_0003_events.csv",
        "C:\Users\Docker\Desktop\event_timeline_db.txt"
    )
    foreach ($f in $outputFiles) {
        if (Test-Path $f) {
            Remove-Item $f -Force -ErrorAction SilentlyContinue
            Write-Host "Removed: $f"
        }
    }

    # Record baseline
    $baseline = @{
        timestamp              = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        data_dir               = $dataDir
        files_present          = @(Get-ChildItem $dataDir -Filter "*.vital" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
        desktop_files_at_start = @(Get-ChildItem "C:\Users\Docker\Desktop" -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    }
    $baseline | ConvertTo-Json -Depth 4 | Out-File "C:\Users\Docker\task_baseline_event_timeline.json" -Encoding UTF8 -Force
    Write-Host "Baseline recorded"

    # Launch Vital Recorder with empty workspace
    $vrExe = Find-VitalRecorderExe
    Launch-VitalRecorderInteractive -VitalRecorderExe $vrExe -WaitSeconds 22

    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Run-InteractiveScript -ScriptPath $dismissScript -TaskName "DismissDialogs_EventTimeline" -WaitSeconds 12
    }

    if (Test-VitalRecorderRunning) {
        Write-Host "Vital Recorder running - agent must open all 3 cases and build event timeline database"
    } else {
        Write-Host "WARNING: Vital Recorder not detected"
    }

    Write-Host "=== cross_case_event_timeline_database setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
