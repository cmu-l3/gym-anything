# Setup script for longest_case_phase_timeline task
# Launches Vital Recorder with an empty workspace.
# The agent must compare all three recordings to identify
# the longest, then analyze its phase structure.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_phase_timeline.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { Write-Host "WARNING: Start-Transcript failed" }

try {
    Write-Host "=== Setting up longest_case_phase_timeline task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    Get-Process -Name "Vital" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Ensure all three data files are available
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
        "C:\Users\Docker\Desktop\longest_case_intraop.csv",
        "C:\Users\Docker\Desktop\phase_analysis.txt"
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
    $baseline | ConvertTo-Json -Depth 4 | Out-File "C:\Users\Docker\task_baseline_phase_timeline.json" -Encoding UTF8 -Force
    Write-Host "Baseline recorded"

    # Launch Vital Recorder with empty workspace
    $vrExe = Find-VitalRecorderExe
    Launch-VitalRecorderInteractive -VitalRecorderExe $vrExe -WaitSeconds 22

    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Run-InteractiveScript -ScriptPath $dismissScript -TaskName "DismissDialogs_PhaseTimeline" -WaitSeconds 12
    }

    if (Test-VitalRecorderRunning) {
        Write-Host "Vital Recorder running - agent must compare all three cases to find the longest"
    } else {
        Write-Host "WARNING: Vital Recorder not detected"
    }

    Write-Host "=== longest_case_phase_timeline setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
